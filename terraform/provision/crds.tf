# -----------------------------------------------------------------------------
# Install Solr operator and Zookeper operators so that their included CRDs will
# be available to cluster users.
# -----------------------------------------------------------------------------

# We install the zookeeper-operator directly rather than letting the
# solr-operator do it so that it will register its CRDs as part of the helm
# install process.
resource "helm_release" "zookeeper-operator" {
  name            = "zookeeper"
  chart           = "zookeeper-operator"
  repository      = "https://charts.pravega.io/"
  version         = "0.2.12"
  namespace       = "kube-system"
  cleanup_on_fail = "true"
  atomic          = "true"
  depends_on = [
    null_resource.cluster-functional,
  ]
}

# TODO: Figure out how we can non-destructively update the CRDs from the
# upstream manifest without uninstalling/reinstalling the operator. We might be
# able do this with a null_resource that triggers on the content of the upstream
# CRD manifest file changing.
resource "helm_release" "solr-operator" {
  name            = "solr"
  chart           = "solr-operator"
  repository      = "https://solr.apache.org/charts"
  version         = "0.4.0"
  namespace       = "kube-system"
  cleanup_on_fail = "true"
  atomic          = "true"
  
  set {
    name  = "zookeeper-operator.install"
    value = "false"
  }
  set {
    name  = "zookeeper-operator.use"
    value = "true"
  }
  
  depends_on = [
    helm_release.zookeeper-operator
  ]
}

