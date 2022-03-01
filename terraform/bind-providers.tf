provider "kubernetes" {
  alias                  = "bind"
  host                   = module.provision.server
  cluster_ca_certificate = base64decode(module.provision.certificate_authority_data)
  token                  = module.provision.token
}
