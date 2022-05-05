terraform {
 backend "s3" {
   bucket         = var.s3_bucket_name
   key            = var.s3_object_name
   region         = var.s3_region
   encrypt        = true
   access_key     = var.s3_aws_access_key_id
   secret_key     = var.s3_aws_secret_access_key
 }
}
