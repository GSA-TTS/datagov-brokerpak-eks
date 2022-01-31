
variable "subdomain" {
  type    = string
  default = ""
}

variable "instance_name" {
  type    = string
  default = ""
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 5
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "instance_types" {
  type    = list
  default = ["m5.large"]
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
