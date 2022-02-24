terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>3.63"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~>2.7"

    }
    random = {
      source = "hashicorp/random"
    }
    template = {
      source = "hashicorp/template"
    }
  }
  required_version = "~> 1.1"
}
