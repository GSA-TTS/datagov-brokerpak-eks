
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
  volume_binding_mode = "WaitForFirstConsumer"

  # The following code uses an optional nested block to define EBS volume parameters
  # References:
  # - https://codeinthehole.com/tips/conditional-nested-blocks-in-terraform/
  # - https://medium.com/@business_99069/terraform-0-12-conditional-block-7d166e4abcbf
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
