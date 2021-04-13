# --------------------------------------------------------------------------
# Install Solr and Zookeeper operators so that the CRDs will be available 
# --------------------------------------------------------------------------
resource "helm_release" "zookeeper-operator" {
  name            = "zookeeper"
  chart           = "zookeeper-operator"
  repository      = "https://charts.pravega.io/"
  namespace       = "kube-system"
  cleanup_on_fail = "true"
  atomic          = "true"
  depends_on = [
    module.vpc,
    aws_eks_fargate_profile.default_namespaces,
  ]
}

resource "helm_release" "solr-operator" {
  name            = "solr"
  chart           = "solr-operator"
  repository      = "https://solr.apache.org/charts"
  namespace       = "kube-system"
  cleanup_on_fail = "true"
  atomic          = "true"

  # We need to wait until the zookeeper-operator is live
  # This should sidestep the issue described here:
  # https://github.com/bloomberg/solr-operator/issues/122
  depends_on = [
    helm_release.zookeeper-operator
  ]
}

