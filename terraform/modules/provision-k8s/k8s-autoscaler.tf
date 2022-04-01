locals {
  karpenter_provisioner = <<-TEMPLATE
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
      limits:
        resources:
          cpu: 1000
      provider:
        launchTemplate: <launch-template-name>
        subnetSelector:
          karpenter.sh/discovery: <cluster-name>
      ttlSecondsAfterEmpty: 30
  TEMPLATE
}

resource "null_resource" "autoscaler-provisioner" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(local.kubeconfig.rendered)
      PROVISIONER_TEMPLATE = replace(replace("${local.karpenter_provisioner}",
        "<launch-template-name>", local.launch_template_name),
        "<cluster-name>", local.cluster_name)
    }

    command = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) apply -f - <<< "$PROVISIONER_TEMPLATE"
    EOF
  }

  depends_on = [
    null_resource.cluster-functional,
    helm_release.karpenter
  ]
}
