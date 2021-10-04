# --------------------------------------------------------------------------
# Install Solr operator so that the included Solr CRDs will be available 
# --------------------------------------------------------------------------

# TODO: Figure out how we can non-destructively update the CRDs from the
# upstream manifest without uninstalling/reinstalling the operator
resource "helm_release" "solr-operator" {
  name            = "solr"
  chart           = "solr-operator"
  repository      = "https://solr.apache.org/charts"
  version         = "0.4.0"
  namespace       = "kube-system"
  cleanup_on_fail = "true"
  atomic          = "true"
  depends_on = [
    null_resource.cluster-functional
  ]
}

