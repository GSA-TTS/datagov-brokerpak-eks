output "kubeconfig" { value = data.template_file.kubeconfig.rendered }
output "server" { value = var.server }
output "certificate_authority_data" { value = var.certificate_authority_data }
output "token" {
  sensitive = true
  value     = base64encode(data.kubernetes_secret.secret.data.token)
}
output "namespace" { value = local.namespace }
