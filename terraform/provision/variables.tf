
variable "zone" {
  description = "existing dns zone that this is under, like test.gov"
  type        = string
}

variable "subdomain" {
  description = "subdomain that is under the zone, so for foo.test.gov, this would be 'foo'"
  type        = string
  default     = ""
}

variable "instance_name" {
  description = "name of the eks cluster"
  type        = string
  default     = ""
}

variable "labels" {
  description = "tags that are applied to most AWS resources"
  type        = map(any)
  default     = {}
}

variable "region" {
  description = "AWS region, like us-west-2"
  type        = string
}
