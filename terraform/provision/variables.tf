variable "aws_access_key_id" {
  type = string
}

variable "aws_secret_access_key" {
  type = string
}

variable "subdomain" {
  type    = string
  default = ""
}

variable "instance_name" {
  type    = string
  default = ""
}

variable "mng_min_capacity" {
  type    = number
  default = 1
}

variable "mng_max_capacity" {
  type    = number
  default = 5
}

variable "mng_desired_capacity" {
  type    = number
  default = 2
}

variable "mng_instance_types" {
  type    = list(any)
  default = ["m4.xlarge"]
}

variable "install_vpc_cni" {
  type    = bool
  default = true
}

variable "labels" {
  type    = map(any)
  default = {}
}

variable "zone" {
  type = string
}

variable "region" {
  type = string
}

variable "write_kubeconfig" {
  type    = bool
  default = false
}
