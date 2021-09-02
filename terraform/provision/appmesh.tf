# ---------------------------------------------------------
# Provision cert-manager using Helm and a self-signed cert
# ---------------------------------------------------------
resource "kubernetes_namespace" "cert-manager" {
  metadata {
    name = "cert-manager"
  }

  depends_on = [
    aws_eks_fargate_profile.default_namespaces
  ]
}

resource "helm_release" "cert-manager" {
  name       = "cert-manager"
  chart      = "cert-manager"
  repository = "https://charts.jetstack.io/"
  version    = "v1.5.3"
  namespace       = "cert-manager"
  cleanup_on_fail = "true"
  atomic          = "true"
  timeout         = 600

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.cert-manager
  ]
}

resource "tls_private_key" "cert-manager" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "cert-manager" {
  key_algorithm   = "RSA"
  private_key_pem = tls_private_key.cert-manager.private_key_pem

  subject {
    common_name  = "appmesh"
    organization = "GSA"
  }

  validity_period_hours = 87600

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "kubernetes_secret" "cert-manager" {
  metadata {
    name      = "ca-key-pair"
    namespace = "default"
  }
  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_self_signed_cert.cert-manager.cert_pem
    "tls.key" = tls_private_key.cert-manager.private_key_pem
  }
}

# Until we can use terraform 0.14+, and thus be able to use kubernetes_manifest,
# we need to do this with kubectl.  :-(
data "template_file" "ca-issuer" {
  template = <<-EOF
apiVersion: cert-manager.io/v1alpha2
kind: Issuer
metadata:
  name: ca-issuer
  namespace: default
spec:
  ca:
    secretName: ca-key-pair
EOF
}

resource "null_resource" "ca-issuer" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(module.eks.kubeconfig)
    }
    command = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) apply -f <(echo '${data.template_file.ca-issuer.rendered}') 
    EOF
  }
  depends_on = [
    helm_release.cert-manager,
    kubernetes_secret.cert-manager
  ]
}


# # ---------------------------------------------------------
# # Provision the App Mesh Controller using Helm
# # ---------------------------------------------------------
# resource "kubernetes_namespace" "appmesh-system" {
#   metadata {
#     name = "appmesh-system"
#   }

#   depends_on = [
#     aws_eks_fargate_profile.default_namespaces
#   ]
# }

# resource "helm_release" "appmesh-controller" {
#   name       = "appmesh-controller"
#   chart      = "eks/appmesh-controller"
#   repository = "https://aws.github.io/eks-charts"
#   version    = "1.4.1"

#   namespace       = "appmesh-system"
#   cleanup_on_fail = "true"
#   atomic          = "true"
#   timeout         = 600

#   depends_on = [
#     kubernetes_namespace.appmesh-system
#   ]
# }

# resource "null_resource" "label" {
#   provisioner "local-exec" {
#     interpreter = ["/bin/bash", "-c"]
#     environment = {
#       KUBECONFIG = base64encode(module.eks.kubeconfig)
#     }
#     command = <<-EOF
#       kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) label namespace default mesh=default ;
#       kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) label namespace default appmesh.k8s.aws/sidecarInjectorWebhook=enabled
#     EOF
#   }
#   depends_on = [
#     aws_eks_fargate_profile.default_namespaces
#   ]
# }
