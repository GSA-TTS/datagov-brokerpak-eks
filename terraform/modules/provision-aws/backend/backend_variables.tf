
variable "s3_bucket_name" {
  type    = string
  default = "static-eks-bucket"
}

variable "s3_object_name" {
  type    = string
  default = "static-eks-deployment"
}

variable "s3_region" {
  type    = string
  default = "us-gov-west-1"
}

variable "s3_aws_access_key_id" {
  type    = string
  default = "super-secret-id"
}

variable "s3_aws_secret_access_key" {
  type    = string
  default = "super-secret-key"
}
