
resource "kubernetes_storage_class" "ebs-sc" {
  metadata {
    name = "ebs-sc"
  }
  parameters = {
    encrypted = "true"
    kmsKeyId  = local.persistent_storage_key_id
  }
  # Storage provisioner retrieved from
  # https://docs.aws.amazon.com/eks/latest/userguide/storage-classes.html
  storage_provisioner    = "kubernetes.io/aws-ebs"
  allow_volume_expansion = true

  # Ensure volumes are created in the correct topology (specifically availability zone)
  # https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode
  volume_binding_mode    = "WaitForFirstConsumer"

  allowed_topologies {
    dynamic "match_label_expressions" {
      for_each = var.single_az ? [1] : []
      content {
        key    = "topology.ebs.csi.aws.com/zone"
        values = ["${var.region}a"]
      }
    }
  }
}
