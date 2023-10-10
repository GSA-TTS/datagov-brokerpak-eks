# This is a workaround to use CRDs in the same Terraform pass as they are made
# available. Explanation:
# https://github.com/GSA/datagov-brokerpak-eks/pull/67#issuecomment-1093641392
resource "helm_release" "autoscaler-provisioner" {
  name       = "autocaler-provisioner"
  repository = "https://charts.itscontained.io"
  chart      = "raw"
  version    = "1.27.2"
  values = [
    <<-EOF
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: eks.amazonaws.com/compute-type
          operator: In
          values: ["fargate"]
      limits:
        resources:
          cpu: 1000
      provider:
        subnetSelector:
          karpenter.sh/discovery: <cluster-name>
      ttlSecondsAfterEmpty: 30
    EOF
  ]
  depends_on = [
    null_resource.cluster-functional,
    helm_release.karpenter
  ]
}
