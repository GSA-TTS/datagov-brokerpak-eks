# === VARS STUFF ===
variable "map_users" {
  description = "Additional IAM users to add to the aws-auth configmap. See examples/basic/variables.tf for example format."
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default = [{
    userarn = "arn:aws:iam::774350622607:user/auditor1",
    username = "auditor1",
    groups = ["audit-team"]
  }]
}

variable "GRAFANA_PWD" {
  description = "Password to be used for accessing the Grafana service"
}



# === HELM STUFF ===

provider "helm" {
  version        = "~> 1.2.3"
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
    load_config_file       = false
  }
}

resource "helm_release" "metrics-server" {
  count     = local.env == "default" ? 1 : 0
  name      = "metrics-server"
  chart     = "stable/metrics-server"
  version   = "2.8.2"
  namespace = "kube-system"

  values    = [
    "${file("./charts/metrics-server/values.yaml")}",
  ]

  provisioner "local-exec" {
    command = "helm --kubeconfig kubeconfig_${module.eks.cluster_id} test -n ${self.namespace} ${self.name}"
  }

  depends_on = [
    module.eks.cluster_id
  ]
}

resource "helm_release" "prometheus" {
  count   = local.env == "default" ? 1 : 0
  name    = "prometheus"
  chart   = "stable/prometheus-operator"
  version = "8.13.11"
  namespace = "monitoring"

  values    = [
#    templatefile("./charts/prometheus/values.yaml", { grafana_pwd = var.GRAFANA_PWD, base_domain = local.base_domain })
    templatefile("./charts/prometheus/values.yaml", { base_domain = local.base_domain })
  ]
  provisioner "local-exec" {
    command = "helm --kubeconfig kubeconfig_${module.eks.cluster_id} test -n ${self.namespace} ${self.name}"
  }

  depends_on = [
    module.eks.cluster_id
  ]
}

### AUTO-SCALER
resource "helm_release" "cluster-autoscaler" {
  count     = local.env == "default" ? 1 : 0
  name = "cluster-autoscaler"
  chart = "stable/cluster-autoscaler"
  version = "7.1.0"
  namespace = "kube-system"
  values    = [
    templatefile("./charts/cluster-autoscaler/values.yaml", { aws_region = local.region }),
  ]

  provisioner "local-exec" {
    command = "helm --kubeconfig kubeconfig_${module.eks.cluster_id} test -n ${self.namespace} ${self.name}"
  }

  depends_on = [
    module.eks.cluster_id
  ]
}


# SETUP INGRESS

resource "aws_acm_certificate" "cert" {
  domain_name               = "*.${local.base_domain}"
# See https://www.terraform.io/docs/providers/aws/r/acm_certificate_validation.html#alternative-domains-dns-validation-with-route-53
#   subject_alternative_names = [
#     "*.${local.cluster_name}.${local.base_domain}",
#     "${local.cluster_name}.${local.base_domain}"
#   ]
  validation_method         = "DNS"
}
resource "aws_route53_zone" "zone" {
  name = local.base_domain
}

resource "aws_route53_record" "cert_validation" {
  name    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_type
  zone_id = aws_route53_zone.zone.zone_id
  records = [aws_acm_certificate.cert.domain_validation_options.0.resource_record_value]
  ttl     = 60
}

# resource "aws_acm_certificate_validation" "cert" {
#   certificate_arn         = aws_acm_certificate.cert.arn
#   validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
# }

resource "helm_release" "ingress" {
  count     = local.env == "default" ? 1 : 0
  name = "ingress"
  chart = "stable/nginx-ingress"
  # version = "1.40.3"
  namespace = "kube-system"
  cleanup_on_fail = "true"
  atomic = "true"

  values    = [
    file("./charts/nginx-ingress/values.yaml"),
    templatefile("./charts/nginx-ingress/values.${local.env}.yaml", { certificate_arn = aws_acm_certificate.cert.arn}),
  ]
  
  provisioner "local-exec" {
    command = "helm --kubeconfig kubeconfig_${module.eks.cluster_id} test -n ${self.namespace} ${self.name}"
  }

  depends_on = [
    module.eks.cluster_id
  ]
}
