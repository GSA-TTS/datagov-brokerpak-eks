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

