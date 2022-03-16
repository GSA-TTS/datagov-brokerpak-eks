# This file contains the variable definitions necessary when the directory is
# used as a standalone module. Leave it out if you're combining this directory
# with the provision-aws module.

# The certificate_authority_data for the k8s instance
variable "certificate_authority_data" {
  type = string
}

# The domain suffix to use for all DNS entries
variable "domain" {
  type = string
}

# The name of the k8s instance we're setting up
variable "instance_name" {
  type    = string
}

# ARN for the key used for EBS volumes
variable "persistent_storage_key_id" {
  type = string
}

# AWS Region
variable "region" {
  type = string
}

# The server for the k8s API
variable "server" {
  type = string
}

# The ID of the Route53 zone where external DNS records for ingresses should be
# maintained
variable "zone_id" {
  type = string
}

# The ARN of an IAM role that is able to manipulate records in the Route53 zone_id.
variable "zone_role_arn" {
  type = string
}

locals {
  certificate_authority_data = var.certificate_authority_data
  cluster_name = "k8s-${substr(sha256(var.instance_name), 0, 16)}"
  domain = var.domain
  persistent_storage_key_id = var.persistent_storage_key_id
  region = var.region
  server = var.server
  zone_id = var.zone_id
  zone_role_arn = var.zone_role_arn
}
