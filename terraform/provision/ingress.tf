locals {
  base_domain = var.zone
  domain      = "${local.subdomain}.${local.base_domain}"
  subdomain   = var.subdomain
}

# We need an OIDC provider for the ALB ingress controller to work
data "tls_certificate" "main" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.main.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Use a convenient module to install the AWS Load Balancer controller
module "aws_load_balancer_controller" {
  # source                    = "/local/path/to/terraform-kubernetes-aws-load-balancer-controller"
  source           = "github.com/GSA/terraform-kubernetes-aws-load-balancer-controller.git?ref=v4.2.0gsa"
  k8s_cluster_type = "eks"
  k8s_namespace    = "kube-system"
  aws_region_name  = data.aws_region.current.name
  k8s_cluster_name = data.aws_eks_cluster.main.name
  alb_controller_depends_on = [
    module.vpc,
    null_resource.cluster-functional,
  ]
  aws_tags = merge(var.labels, { "domain" = local.domain })
}

# ---------------------------------------------------------
# Provision the Ingress Controller using Helm
# ---------------------------------------------------------
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  version    = "3.37.0"

  namespace       = "kube-system"
  cleanup_on_fail = "true"
  atomic          = "true"
  timeout         = 600

  dynamic "set" {
    for_each = {
      "controller.service.externalTrafficPolicy"     = "Local",
      "controller.service.type"                      = "NodePort",
      "controller.config.server-tokens"              = false,
      "controller.config.use-proxy-protocol"         = false,
      "controller.config.compute-full-forwarded-for" = true,
      "controller.config.use-forwarded-headers"      = true,
      "controller.metrics.enabled"                   = true,
      "controller.autoscaling.maxReplicas"           = 1,
      "controller.autoscaling.minReplicas"           = 1,
      "controller.autoscaling.enabled"               = true,
      "controller.publishService.enabled"            = false,
      "controller.extraArgs.publish-status-address"  = local.domain,
      "serviceAccount.create"                        = true,
      "rbac.create"                                  = true,
      "clusterName"                                  = module.eks.cluster_id,
      "region"                                       = local.region,
      "vpcId"                                        = module.vpc.aws_vpc_id,
      "aws_iam_role_arn"                             = module.aws_load_balancer_controller.aws_iam_role_arn
    }
    content {
      name  = set.key
      value = set.value
    }
  }
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
  depends_on = [
    null_resource.cluster-functional,
  ]
}

# Give the controller time to react to any recent events (eg an ingress was
# removed and an ALB needs to be deleted) before actually removing it.
resource "time_sleep" "alb_controller_destroy_delay" {
  depends_on       = [module.aws_load_balancer_controller]
  destroy_duration = "30s"
}


resource "aws_wafv2_web_acl" "waf_acl" {
  name        = "eks-${local.cluster_name}"
  description = "EKS WAF rule"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = {
      0 = "AWS-AWSManagedRulesCommonRuleSet",
      1 = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      2 = "AWS-AWSManagedRulesSQLiRuleSet"
      3 = "AWS-AWSManagedRulesUnixRuleSet"
      4 = "AWS-AWSManagedRulesLinuxRuleSet"
      5 = "AWS-AWSManagedRulesAmazonIpReputationList"
    }
    content {
      priority = rule.key
      name     = rule.value

      override_action {
        count {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = element(split("-", rule.value), 0) # what's before the -
          name        = element(split("-", rule.value), 1) # what's after the -
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = false
        metric_name                = rule.value
        sampled_requests_enabled   = true
      }
    }
  }

  tags = {
    EKSCluster = local.cluster_name
  }
  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "eks-${local.cluster_name}"
    sampled_requests_enabled   = true
  }
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
      "alb.ingress.kubernetes.io/actions.ssl-redirect"       = "{\"Type\": \"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}",
      "alb.ingress.kubernetes.io/backend-protocol"           = "HTTPS",
      "alb.ingress.kubernetes.io/certificate-arn"            = aws_acm_certificate.cert.arn,
      "alb.ingress.kubernetes.io/healthcheck-path"           = "/",
      "alb.ingress.kubernetes.io/listen-ports"               = "[{\"HTTP\":80}, {\"HTTPS\":443}]",
      "alb.ingress.kubernetes.io/load-balancer-attributes"   = "routing.http2.enabled=true,idle_timeout.timeout_seconds=60",
      "alb.ingress.kubernetes.io/scheme"                     = "internet-facing",
      "alb.ingress.kubernetes.io/shield-advanced-protection" = "false",
      "alb.ingress.kubernetes.io/ssl-policy"                 = "ELBSecurityPolicy-TLS-1-2-2017-01",
      "alb.ingress.kubernetes.io/target-type"                = "ip",
      "alb.ingress.kubernetes.io/wafv2-acl-arn"              = aws_wafv2_web_acl.waf_acl.arn,
      "kubernetes.io/ingress.class"                          = "alb",
    }
  }

  spec {
    rule {
      http {
        path {
          path = "/*"
          backend {
            service_name = "ssl-redirect"
            service_port = "use-annotation"
          }
        }
        path {
          path = "/*"
          backend {
            service_name = "ingress-nginx-controller"
            service_port = "443"
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    time_sleep.alb_controller_destroy_delay,
    module.aws_load_balancer_controller,
  ]
}


# -----------------------------------------------------------------
# SETUP ROUTE53 ACM Certificate and DNS Validation
# -----------------------------------------------------------------

# get externally configured DNS Zone 
data "aws_route53_zone" "zone" {
  name = local.base_domain
}

# Create Hosted Zone for Cluster specific Subdomain name
resource "aws_route53_zone" "cluster" {
  name = local.domain
  # There may be extraneous DNS records from external-dns; that's expected.
  force_destroy = true
  tags = merge(var.labels, {
    Environment = local.cluster_name
    domain      = local.domain
  })
}

# Create the NS record in main domain hosted zone for sub domain hosted zone
resource "aws_route53_record" "cluster-ns" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = local.domain
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.cluster.name_servers
}

# Create ACM certificate for the sub-domain
resource "aws_acm_certificate" "cert" {
  domain_name = local.domain
  # See https://www.terraform.io/docs/providers/aws/r/acm_certificate_validation.html#alternative-domains-dns-validation-with-route-53
  subject_alternative_names = [
    "*.${local.domain}"
  ]
  validation_method = "DNS"
  tags = merge(var.labels, {
    domain      = local.domain
    environment = local.cluster_name
  })
}

# Validate the certificate using DNS method
resource "aws_route53_record" "cert_validation" {
  name    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_type
  zone_id = aws_route53_zone.cluster.id
  records = [tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

# Get the Ingress for the ALB
data "aws_elb_hosted_zone_id" "elb_zone_id" {}

# Create CNAME record in sub-domain hosted zone for the ALB
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.cluster.id
  name    = local.domain
  type    = "A"

  alias {
    name                   = kubernetes_ingress.alb_to_nginx.load_balancer_ingress.0.hostname
    zone_id                = data.aws_elb_hosted_zone_id.elb_zone_id.id
    evaluate_target_health = true
  }
}
