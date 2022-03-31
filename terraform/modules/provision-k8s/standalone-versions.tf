# This file contains the version definitions necessary when the directory is
# used as a standalone module. Leave it out if you're combining this directory
# with the provision-aws module

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.63"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~>2.4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~>2.7"
    }

  }
  required_version = "~> 1.1"
}
