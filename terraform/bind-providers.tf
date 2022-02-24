# resource "local_file" "bind-kubeconfig" {
#   sensitive_content = module.provision.admin_kubeconfig
#   filename          = "./kubeconfig-for-bind"
#   file_permission   = "0600"
#   depends_on = [
#     module.provision
#   ]
# }
# provider "kubernetes" {
#   alias = "bind"
#   config_path = local_file.bind-kubeconfig.filename
# }

provider "kubernetes" {
  alias = "bind"
  host                   = module.provision.host
  cluster_ca_certificate = base64decode(module.provision.cluster_ca_certificate)
  token                  = module.provision.token
}
