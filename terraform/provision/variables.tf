
variable "subdomain" {
  type    = string
  default = ""
}

variable "instance_name" {
  type    = string
  default = ""
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

variable "ingress_allowed" {
  type = list
  description = "A list of IP Range [\"x.x.x.x/x\", ...] to allow ingress traffic"
  default = null
}

variable "egress_allowed" {
  type = list
  description = "A list of IP Range [\"x.x.x.x/x\", ...] to allow egress traffic"
  default = null
}

variable "write_kubeconfig" {
  type = bool
  default = false
}
