
resource "kubernetes_storage_class" "ebs-sc" {
  metadata {
    name = "ebs-sc"
  }
  parameters = {
    encrypted = "true"
    kmsKeyId  = var.persistent_storage_key_id
  }
  # Storage provisioner retrieved from
  # https://docs.aws.amazon.com/eks/latest/userguide/storage-classes.html
  storage_provisioner    = "kubernetes.io/aws-ebs"
  allow_volume_expansion = true
}
