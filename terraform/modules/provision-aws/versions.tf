terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.19"
      configuration_aliases = [aws.dnssec-key-provider]
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~>2.11"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~>2.23"
    }

    local = {
      source  = "hashicorp/local"
      version = "~>2.4"
    }
    http = {
      source  = "hashicorp/http"
      version = "~>3.4"
    }

    null = {
      source = "hashicorp/null"
    }
    template = {
      source = "hashicorp/template"
    }
    time = {
      source = "hashicorp/time"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
  required_version = "~> 1.1"
}
