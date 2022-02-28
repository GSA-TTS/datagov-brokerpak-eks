provider "kubernetes" {
  alias = "bind"
  host                   = module.provision.host
  cluster_ca_certificate = base64decode(module.provision.cluster_ca_certificate)
  token                  = module.provision.token
}
