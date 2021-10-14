
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
  type = string
  description = "A single IP Range (x.x.x.x/x) to allow ingress traffic"
  default = ""
}

variable "ingress_disallowed" {
  type = list
  description = "A list of IP Ranges [\"x.x.x.x/x\", ...] to restrict ingress traffic"
  default = [""]
}

variable "egress_allowed" {
  type = string
  description = "A single IP Range (x.x.x.x/x) to allow egress traffic"
  default = ""
}

variable "egress_disallowed" {
  type = list
  description = "A list of IP Ranges [\"x.x.x.x/x\", ...] to restrict egress traffic"
  default = [""]
}
