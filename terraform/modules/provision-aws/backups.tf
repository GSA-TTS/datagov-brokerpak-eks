
# If an existing backup bucket wasn't supplied, we provision a bucket bound to
# the lifecycle of the cluster, and IAM creds that can access it. 

# These local values are needed when setting up Velero on the k8s/helm side.
locals {
  backup_bucket_fqdn       = var.backup_bucket_fqdn != null ? var.backup_bucket_fqdn : aws_s3_bucket.backups[0].bucket_domain_name
  backup_region            = var.backup_region != null ? var.backup_region : aws_s3_bucket.backups[0].region
  backup_secret_access_key = var.backup_secret_access_key != null ? var.backup_secret_access_key : module.backups-user[0].secret_access_key
  backup_access_key_id     = var.backup_access_key_id != null ? var.backup_access_key_id : module.backups-user[0].access_key_id
}

resource "aws_s3_bucket" "backups" {
  count  = var.backup_bucket_fqdn != null ? 0 : 1
  bucket = "${local.cluster_name}-backups"
}

module "backups-user" {
  count   = var.backup_bucket_fqdn != null ? 0 : 1
  source  = "cloudposse/iam-s3-user/aws"
  version = "0.15.9"
  name    = "${local.cluster_name}-backups"

  s3_resources = [ aws_s3_bucket.backups[0].arn ]

  # Based on 
  s3_actions = [
    "s3:GetObject",
    "s3:DeleteObject",
    "s3:PutObject",
    "s3:AbortMultipartUpload",
    "s3:ListMultipartUploadParts"
  ]
}
