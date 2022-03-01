variable "server" { 
    type = string 
}

variable "certificate_authority_data" {
    type = string 
}

variable "token" { 
    type = string 
}

provider "kubernetes" {
  host                   = var.server
  cluster_ca_certificate = base64decode(var.certificate_authority_data)
  token                  = var.token
}
