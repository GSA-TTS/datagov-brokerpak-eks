terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 3.63"
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
