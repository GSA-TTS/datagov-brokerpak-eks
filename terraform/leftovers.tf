# === VARS STUFF ===
variable "map_users" {
  description = "Additional IAM users to add to the aws-auth configmap. See examples/basic/variables.tf for example format."
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default = [{
    userarn  = "arn:aws:iam::774350622607:user/auditor1",
    username = "auditor1",
    groups   = ["audit-team"]
  }]
}

variable "GRAFANA_PWD" {
  description = "Password to be used for accessing the Grafana service"
}

### METRICS

resource "helm_release" "metrics-server" {
  count     = local.env == "default" ? 1 : 0
  name      = "metrics-server"
  chart     = "stable/metrics-server"
  version   = "2.8.2"
  namespace = "kube-system"

  values = [
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
  count     = local.env == "default" ? 1 : 0
  name      = "prometheus"
  chart     = "stable/prometheus-operator"
  version   = "8.13.11"
  namespace = "monitoring"

  values = [
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
  name      = "cluster-autoscaler"
  chart     = "stable/cluster-autoscaler"
  version   = "7.1.0"
  namespace = "kube-system"
  values = [
    templatefile("./charts/cluster-autoscaler/values.yaml", { aws_region = local.region }),
  ]

  provisioner "local-exec" {
    command = "helm --kubeconfig kubeconfig_${module.eks.cluster_id} test -n ${self.namespace} ${self.name}"
  }

  depends_on = [
    module.eks.cluster_id
  ]
}
