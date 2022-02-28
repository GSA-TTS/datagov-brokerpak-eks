terraform {
  required_version = ">= 1.1.5"
  required_providers {
    # The aws provider should be configured for where most EKS resources should
    # land. The aws.dnssec-key-provider should be an aliased provider
    # configuration pointing specifically at the us-east-1 region. We are
    # required to set up KMS keys in that region in order for them to be usable
    # for setting up a DNSSEC KSK in Route53.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.63"
      configuration_aliases = [ aws.dnssec-key-provider ]
    }
  }
}

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


module "provision" {
  source = "./modules/provision"
  providers = {
    aws                     = aws
    aws.dnssec-key-provider = aws.dnssec-key-provider
    kubernetes = kubernetes.provision
    helm = helm.provision
  }
  aws_access_key_id = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  install_vpc_cni = true
  instance_name = var.instance_name
  labels = var.labels
  mng_instance_types = var.mng_instance_types
  mng_min_capacity = var.mng_min_capacity
  mng_max_capacity = var.mng_max_capacity
  mng_desired_capacity = var.mng_desired_capacity
  region = var.region
  subdomain = var.subdomain
  write_kubeconfig = var.write_kubeconfig
  zone = var.zone
}

# There's more to be done on hoisting provider configuration out before we can
# uncomment this module! 
module "bind" { 
  source = "./modules/bind" 
  providers = { 
    kubernetes = kubernetes.bind
  }  
  instance_name = var.instance_name 
  depends_on = [
    module.provision
  ]
}
