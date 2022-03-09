# The domain suffix to use for all DNS entries
variable "domain" {
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

# The name of the k8s instance we're setting up
variable "instance_name" {
  type    = string
  default = ""
}

# The server for the k8s API
variable "server" {
  type = string
}

# The certificate_authority_data for the k8s instance
variable "certificate_authority_data" {
  type = string
}

# Information about the current region
data "aws_region" "current" {}

