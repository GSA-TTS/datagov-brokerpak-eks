# Credit where credit is due:
#
# * The original sample we built around came from this blog post by Chris Weibel
#   at Stark and Wayne:
#   https://starkandwayne.com/blog/65-lines-of-terraform-for-a-new-vpc-eks-node-group-fargate-profile/
#   
#
# * The method use below for securely specifying the kubeconfig to provisioners
#   without spilling secrets into the logs comes from:
#   https://medium.com/citihub/a-more-secure-way-to-call-kubectl-from-terraform-1052adf37af8

output "kubeconfig" { value = module.eks.kubeconfig }

locals {
  cluster_name    = "k8s-${random_id.cluster.hex}"
  cluster_version = "1.18"
  region          = "us-east-1"
  base_domain     = "ssb.datagov.us"
  ingress_gateway_annotations = {
    "controller.service.externalTrafficPolicy"     = "Local",
    "controller.service.type"                      = "NodePort",
    "controller.config.server-tokens"              = "false",
    "controller.config.use-proxy-protocol"         = "false",
    "controller.config.compute-full-forwarded-for" = "true",
    "controller.config.use-forwarded-headers"      = "true",
    "controller.metrics.enabled"                   = "true",
    "controller.autoscaling.maxReplicas"           = "1",
    "controller.autoscaling.minReplicas"           = "1",
    "controller.autoscaling.enabled"               = "true",
    "controller.publishService.enabled"            = "true",
    "serviceAccount.create"                        = "true",
    "rbac.create"                                  = "true"
  }
}

# Confirm that the necessary CLI binaries are present
resource "null_resource" "prerequisite_binaries_present" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      which aws-iam-authenticator git helm kubectl
    EOF
  }
}

resource "random_id" "cluster" {
  byte_length = 8

  # If the necessary CLI binaries are not present, then we'll only get partway
  # through provisioning before we are stopped cold as we try to use them,
  # leaving everything in a poor state. We want to check for them as early as we
  # can to avoid that. As this random_id is key to a bunch of other
  # provisioning, we add an explicit dependency here to ensure the check for the
  # binaries happens early.
  depends_on = [
    null_resource.prerequisite_binaries_present
  ]
}

provider "aws" {
  # We need at least 3.16.0 because it fixes a problem with creating/deleting
  # Fargate profiles in parallel. See this issue for more information:
  # https://github.com/hashicorp/terraform-provider-aws/issues/13372#issuecomment-729689441
  # version = "~> 3.16.0"
  # Using 2.67.0 so that Route53 that was developed using the eks cluster works with the Fargate
  version = "~> 2.67.0"
  region  = local.region
}


module "vpc" {
  source = "github.com/FairwindsOps/terraform-vpc.git?ref=v5.0.1"

  aws_region           = local.region
  az_count             = 2
  aws_azs              = "us-east-1b, us-east-1c"
  single_nat_gateway   = 1
  multi_az_nat_gateway = 0

  enable_s3_vpc_endpoint = "true"

  # Tag subnets for use by AWS' load-balancers and the ALB ingress controllers
  # See https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  global_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_prod_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  # version         = "13.2.1"
  # eks 13.2.1 has dependency for aws provider 3.16.0 so moving eks version to 12.1.0
  version         = "12.1.0"
  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version
  vpc_id          = module.vpc.aws_vpc_id
  subnets         = module.vpc.aws_subnet_private_prod_ids
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_in_days = 180
  manage_aws_auth = false
  write_kubeconfig = false
}

data "aws_eks_cluster" "main" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_id
}

resource "aws_iam_role" "iam_role_fargate" {
  name = "eks-fargate-profile-${local.cluster_name}"
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}


# -----------------------------------------------------------------------------------
# Fargate Logging Policy and Policy Attachment for the existing Fargate pod execution IAM role
# -----------------------------------------------------------------------------------
resource "aws_iam_policy" "AmazonEKSFargateLoggingPolicy" {
  name   = "AmazonEKSFargateLoggingPolicy"
  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:CreateLogGroup",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "AmazonEKSFargateLoggingPolicy" {
  policy_arn = aws_iam_policy.AmazonEKSFargateLoggingPolicy.arn
  role       = aws_iam_role.iam_role_fargate.name
}

# --------------------------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "AmazonEKSFargatePodExecutionRolePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.iam_role_fargate.name
}

resource "aws_eks_fargate_profile" "default_namespaces" {
  depends_on             = [module.eks]
  cluster_name           = data.aws_eks_cluster.main.name
  fargate_profile_name   = "default-namespaces-${local.cluster_name}"
  pod_execution_role_arn = aws_iam_role.iam_role_fargate.arn
  subnet_ids             = module.vpc.aws_subnet_private_prod_ids
  timeouts {
    # For reasons unknown, Fargate profiles can take upward of 20 minutes to
    # delete! I've never seen them go past 30m, though, so this seems OK.
    delete = "30m"
  }
  selector {
    namespace = "default"
  }
  selector {
    namespace = "kube-system"
  }
}

# Per AWS docs, you have to patch the coredns deployment to remove the
# constraint that it wants to run on ec2, then restart it.
resource "null_resource" "coredns_restart_on_fargate" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(module.eks.kubeconfig)
    }
    # Note the "rollout status" command blocks until the "rollout restart" is
    # complete. We do this intentionally because the cluster basically isn't
    # functional until coredns is operating (for example, helm deployments may
    # timeout).
    command = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) \
        patch deployment coredns \
        --namespace kube-system \
        --type=json \
        -p='[{"op": "remove", "path": "/spec/template/metadata/annotations", "value": "eks.amazonaws.com/compute-type"}]' && \
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) rollout restart -n kube-system deployment coredns && \
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) rollout status -n kube-system deployment coredns
    EOF
  }
  depends_on = [
    module.eks.cluster_id,
    aws_eks_fargate_profile.default_namespaces
  ]
}

# ---------------------------------------------------------------------------------------------
# Fargate logging by fluentbit requires namespace aws-observability and Configmap
# ---------------------------------------------------------------------------------------------

# Configure Kubernetes namespace aws-observability by adding the aws-observability annotation. This
# annotation is supported in terraform 0.13 or higher. So kubectl is used to provision the namespace.
data "template_file" "logging" {
  template = <<EOF
kind: Namespace
apiVersion: v1
metadata:
  name: aws-observability
  labels:
    aws-observability: enabled
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: aws-logging
  namespace: aws-observability
data:
  output.conf: |
    [OUTPUT]
        Name cloudwatch_logs
        Match   *
        region ${local.region}
        log_group_name fluent-bit-cloudwatch-${local.cluster_name}
        log_stream_prefix from-fluent-bit-
        auto_create_group On
EOF
}

resource "null_resource" "namespace_fargate_logging" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(module.eks.kubeconfig)
    }
    command     = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) apply -f <(echo '${data.template_file.logging.rendered}') 
    EOF
  }
  depends_on = [
    null_resource.coredns_restart_on_fargate,
    aws_eks_fargate_profile.default_namespaces
  ]
}

# ----------------------------------------------------------------------------------------------------


# We need an OIDC provider for the ALB ingress controller to work
data "tls_certificate" "main" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}
resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.main.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
    command     = "aws-iam-authenticator"
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    load_config_file       = false
    config_path            = "./kubeconfig_${module.eks.cluster_id}"
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
      command     = "aws-iam-authenticator"
    }
  }
  # Helm 2.0.1 seems to have issues with alias. When alias is removed the helm_release provider working
  # Using Helm < 2.0.1 version seem to solve the issue.
  # version = "~> 1.2"
  version = "1.2.0"
}

data "aws_region" "current" {}

# Use a convenient module to install the AWS Load Balancer controller
module "aws_load_balancer_controller" {
  source = "github.com/GSA/terraform-kubernetes-aws-load-balancer-controller.git?ref=v4.1.0"
  # source                    = "/local/path/to/terraform-kubernetes-aws-load-balancer-controller"
  k8s_cluster_type          = "eks"
  k8s_namespace             = "kube-system"
  aws_region_name           = data.aws_region.current.name
  k8s_cluster_name          = data.aws_eks_cluster.main.name
  alb_controller_depends_on = [module.vpc, null_resource.coredns_restart_on_fargate,null_resource.namespace_fargate_logging]

}


# ---------------------------------------------------------
# Provision the Ingress Controller using Helm
# ---------------------------------------------------------
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  # version    = "0.5.2"

  namespace       = "kube-system"
  cleanup_on_fail = "true"
  atomic          = "true"
  timeout         = 600

  dynamic "set" {
    for_each = local.ingress_gateway_annotations
    content {
      name  = set.key
      value = set.value
      type  = "string"
    }
  }
  # set {
  #   name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-cert"
  #   value = aws_acm_certificate.cert.id
  # }
  values = [<<-VALUES
    controller: 
      extraArgs: 
        http-port: 8080 
        https-port: 8543 
      containerPort: 
        http: 8080 
        https: 8543 
      service: 
        ports: 
          http: 80 
          https: 443 
        targetPorts: 
          http: 8080 
          https: 8543 
      image: 
        allowPrivilegeEscalation: false
    VALUES
  ]
  # provisioner "local-exec" {
  #   interpreter = ["/bin/bash", "-c"]
  #   environment = {
  #     KUBECONFIG = base64encode(module.eks.kubeconfig)
  #   }
  #   command = "helm --kubeconfig <(echo $KUBECONFIG | base64 -d) test --logs -n ${self.namespace} ${self.name}"
  # }
  set {
    name  = "clusterName"
    value = module.eks.cluster_id
  }
  set {
    name  = "region"
    value = local.region
  }
  set {
    name  = "vpcId"
    value = module.vpc.aws_vpc_id
  }
  set {
    name  = "aws_iam_role_arn"
    value = module.aws_load_balancer_controller.aws_iam_role_arn
  }
  depends_on = [module.aws_load_balancer_controller]
}

# Give the controller time to react to any recent events (eg an ingress was
# removed and an ALB needs to be deleted) before actually removing it.
resource "time_sleep" "alb_controller_destroy_delay" {
  depends_on       = [module.aws_load_balancer_controller]
  destroy_duration = "30s"
}

resource "kubernetes_ingress" "alb_to_nginx" {
  wait_for_load_balancer = true
  metadata {
    name      = "alb-ingress-to-nginx-ingress"
    namespace = "kube-system"

    labels = {
      app = "nginx"
    }

    annotations = {
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "kubernetes.io/ingress.class"                = "alb"
    }
  }

  spec {
    rule {
      http {
        path {
          path = "/*"
          backend {
            service_name = "ingress-nginx-controller"
            service_port = "80"
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    time_sleep.alb_controller_destroy_delay,
    module.aws_load_balancer_controller
  ]
}

# -----------------------------------------------------------------
# SETUP ROUTE53 ACM Certificate and DNS Validation
# -----------------------------------------------------------------

# get externally configured DNS Zone 
data "aws_route53_zone" "zone" {
  name       = local.base_domain
  depends_on = [module.aws_load_balancer_controller, helm_release.ingress_nginx, kubernetes_ingress.alb_to_nginx]
}

# Create Hosted Zone for Cluster specific Subdomain name
resource "aws_route53_zone" "cluster" {
  name = "${local.cluster_name}.${local.base_domain}"

  tags = {
    Environment = local.cluster_name
  }
  depends_on = [data.aws_route53_zone.zone]
}

# Create the NS record in main domain hosted zone for sub domain hosted zone
resource "aws_route53_record" "cluster-ns" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "${local.cluster_name}.${local.base_domain}"
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.cluster.name_servers

  depends_on = [
    aws_route53_zone.cluster,
    data.aws_route53_zone.zone,
  ]
}

# Create ACM certificate for the sub-domain
resource "aws_acm_certificate" "cert" {
  domain_name = "${local.cluster_name}.${local.base_domain}"
  # See https://www.terraform.io/docs/providers/aws/r/acm_certificate_validation.html#alternative-domains-dns-validation-with-route-53
  subject_alternative_names = [
    "*.${local.cluster_name}.${local.base_domain}"
  ]
  validation_method = "DNS"
  tags = {
    Name        = "${local.cluster_name}.${local.base_domain}"
    environment = local.cluster_name
  }
  depends_on = [
    aws_route53_record.cluster-ns,
  ]
}

# Validate the certificate using DNS method
resource "aws_route53_record" "cert_validation" {
  name       = aws_acm_certificate.cert.domain_validation_options.0.resource_record_name
  type       = aws_acm_certificate.cert.domain_validation_options.0.resource_record_type
  zone_id    = aws_route53_zone.cluster.id
  records    = [aws_acm_certificate.cert.domain_validation_options.0.resource_record_value]
  ttl        = 60
  depends_on = [aws_route53_record.cluster-ns]
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

# Get the Ingress for the ALB
data "aws_elb_hosted_zone_id" "elb_zone_id" {}

# Wait 30 seconds before trying to use the ingress-nginx ALB hostname in DNS
resource "time_sleep" "nginx_alb_creation_delay" {
  create_duration = "30s"
  depends_on      = [kubernetes_ingress.alb_to_nginx]
}

# Create CNAME record in sub-domain hosted zone for the ALB
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.cluster.id
  name    = "${local.cluster_name}.${local.base_domain}"
  type    = "A"

  alias {
    name                   = kubernetes_ingress.alb_to_nginx.load_balancer_ingress.0.hostname
    zone_id                = data.aws_elb_hosted_zone_id.elb_zone_id.id
    evaluate_target_health = true
  }
  depends_on = [
    aws_acm_certificate.cert,
    aws_acm_certificate_validation.cert,
    time_sleep.nginx_alb_creation_delay
  ]
}
