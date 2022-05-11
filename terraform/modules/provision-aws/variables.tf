# Required Variables

variable "instance_name" {
  type    = string
  default = ""
}

variable "region" {
  type = string
}

variable "subdomain" {
  type    = string
  default = ""
}

variable "zone" {
  type = string
}

# Important Configuration Variables
# (optional, but operationally important)

variable "control_plane_ingress_cidrs" {
  type    = list(string)
  default = ["52.222.122.97/32", "52.222.123.172/32"]
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

variable "single_az" {
  type    = bool
  default = false
}

# Completely optional Variables

variable "labels" {
  type    = map(any)
  default = {}
}

variable "write_kubeconfig" {
  type    = bool
  default = false
}
