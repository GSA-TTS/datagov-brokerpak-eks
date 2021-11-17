# -----------------------------------------------------------------------------
# Install Solr operator and Zookeper operators so that their included CRDs will
# be available to cluster users.
# -----------------------------------------------------------------------------

# We install the zookeeper-operator directly rather than letting the
# solr-operator do it so that it will register and unregister its CRDs as part
# of the helm install process.
resource "helm_release" "zookeeper-operator" {
  name       = "zookeeper"
  chart      = "zookeeper-operator"
  repository = "https://charts.pravega.io/"
  version    = "0.2.12"
  namespace  = "kube-system"
  set {
    # See https://github.com/pravega/zookeeper-operator/issues/324#issuecomment-829267141
    name  = "hooks.delete"
    value = "false"
  }

  depends_on = [
    null_resource.cluster-functional,
  ]
}

# TODO: Figure out how we can non-destructively update the CRDs from the
# upstream manifest without uninstalling/reinstalling the operator. See upgrade
# notes here:
# https://artifacthub.io/packages/helm/apache-solr/solr-operator#managing-crds
#
# We might be able do this with a null_resource that triggers on the content of
# the upstream CRD manifest file changing.
resource "helm_release" "solr-operator" {
  name            = "solr"
  chart           = "solr-operator"
  repository      = "https://solr.apache.org/charts"
  version         = "0.3.0"
  namespace       = "kube-system"

  set {
    name  = "zookeeper-operator.use"
    value = "true"
  }

  set {
    name  = "zookeeper-operator.install"
    value = "false"
  }

  depends_on = [
    null_resource.cluster-functional,
  ]
}

