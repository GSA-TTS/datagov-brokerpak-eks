output "kubeconfig" { value = data.template_file.kubeconfig.rendered }
output "server" { value = data.aws_eks_cluster.main.endpoint }
output "certificate_authority_data" { value = data.aws_eks_cluster.main.certificate_authority[0].data }
output "token" {
  sensitive = true
  value     = base64encode(data.kubernetes_secret.secret.data.token)
}
output "namespace" { value = local.namespace }
