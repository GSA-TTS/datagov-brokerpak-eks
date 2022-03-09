provider "kubernetes" {
  alias                  = "bind"
  host                   = module.provision-aws.server
  cluster_ca_certificate = base64decode(module.provision-aws.certificate_authority_data)
  token                  = module.provision-k8s.token
}
