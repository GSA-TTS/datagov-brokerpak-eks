terraform {
  required_version = ">= 1.1.5"
  required_providers {
    # The aws provider should be configured for where most EKS resources should
    # land. The aws.dnssec-key-provider should be an aliased provider
    # configuration pointing specifically at the us-east-1 region. We are
    # required to set up KMS keys in that region in order for them to be usable
    # for setting up a DNSSEC KSK in Route53.
    # Documentation on using aliased providers in a module:
    # https://www.terraform.io/language/modules/develop/providers#provider-aliases-within-modules
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 3.63"
      configuration_aliases = [aws.dnssec-key-provider]
    }
  }
}

output "domain_name" {
  value = module.provision-aws.domain_name
}

output "certificate_authority_data" {
  value = module.bind.certificate_authority_data
}

output "server" {
  value = module.bind.server
}

output "token" {
  value     = module.bind.token
  sensitive = true
}

output "namespace" {
  value = module.bind.namespace
}

output "kubeconfig" {
  value = module.bind.kubeconfig
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

module "provision-aws" {
  source = "./modules/provision-aws"
  providers = {
    aws                     = aws
    aws.dnssec-key-provider = aws.dnssec-key-provider
  }
  instance_name        = var.instance_name
  labels               = var.labels
  mng_instance_types   = var.mng_instance_types
  mng_min_capacity     = var.mng_min_capacity
  mng_max_capacity     = var.mng_max_capacity
  mng_desired_capacity = var.mng_desired_capacity
  use_hardened_ami     = var.use_hardened_ami
  region               = var.region
  subdomain            = var.subdomain
  write_kubeconfig     = var.write_kubeconfig
  zone                 = var.zone
}

module "provision-k8s" {
  source = "./modules/provision-k8s"
  providers = {
    aws        = aws
    kubernetes = kubernetes.provision
    helm       = helm.provision
  }
  certificate_authority_data = module.provision-aws.certificate_authority_data
  domain                     = module.provision-aws.domain_name
  instance_name              = var.instance_name
  persistent_storage_key_id  = module.provision-aws.persistent_storage_key_id
  region                     = var.region
  server                     = module.provision-aws.server
  zone_id                    = module.provision-aws.zone_id
  zone_role_arn              = module.provision-aws.zone_role_arn
}

module "bind" {
  source = "./modules/bind"
  providers = {
    kubernetes = kubernetes.bind
  }
  instance_name = var.instance_name
  depends_on = [
    module.provision-k8s
  ]
}
