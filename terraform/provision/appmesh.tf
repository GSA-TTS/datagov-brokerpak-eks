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
  set {
    # https://github.com/jetstack/cert-manager/issues/3237
    name  = "webhook.securePort"
    value = "10260"
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
apiVersion: cert-manager.io/v1
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


# ---------------------------------------------------------
# Provision the App Mesh Controller using Helm
# ---------------------------------------------------------
resource "kubernetes_namespace" "appmesh-system" {
  metadata {
    name = "appmesh-system"
  }

  depends_on = [
    null_resource.ca-issuer
  ]
}

# This role is assigned with IRSA to the appmesh controller
resource "aws_iam_role" "appmesh-controller" {
  name = "appmesh-controller-${local.cluster_name}"
  tags = var.labels
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "appmesh",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_url}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${local.oidc_url}:sub": "system:serviceaccount:appmesh-system:appmesh-controller"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "appmesh-controller" {
  name_prefix = "${local.cluster_name}-AWSAppMeshK8sControllerIAMPolicy"
  role        = aws_iam_role.appmesh-controller.name
  policy      = <<-EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
        "appmesh:ListVirtualRouters",
        "appmesh:ListVirtualServices",
        "appmesh:ListRoutes",
        "appmesh:ListGatewayRoutes",
        "appmesh:ListMeshes",
        "appmesh:ListVirtualNodes",
        "appmesh:ListVirtualGateways",
        "appmesh:DescribeMesh",
        "appmesh:DescribeVirtualRouter",
        "appmesh:DescribeRoute",
        "appmesh:DescribeVirtualNode",
        "appmesh:DescribeVirtualGateway",
        "appmesh:DescribeGatewayRoute",
        "appmesh:DescribeVirtualService",
        "appmesh:CreateMesh",
        "appmesh:CreateVirtualRouter",
        "appmesh:CreateVirtualGateway",
        "appmesh:CreateVirtualService",
        "appmesh:CreateGatewayRoute",
        "appmesh:CreateRoute",
        "appmesh:CreateVirtualNode",
        "appmesh:UpdateMesh",
        "appmesh:UpdateRoute",
        "appmesh:UpdateVirtualGateway",
        "appmesh:UpdateVirtualRouter",
        "appmesh:UpdateGatewayRoute",
        "appmesh:UpdateVirtualService",
        "appmesh:UpdateVirtualNode",
        "appmesh:DeleteMesh",
        "appmesh:DeleteRoute",
        "appmesh:DeleteVirtualRouter",
        "appmesh:DeleteGatewayRoute",
        "appmesh:DeleteVirtualService",
        "appmesh:DeleteVirtualNode",
        "appmesh:DeleteVirtualGateway"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "iam:CreateServiceLinkedRole"
                ],
                "Resource": "arn:aws:iam::*:role/aws-service-role/appmesh.amazonaws.com/AWSServiceRoleForAppMesh",
                "Condition": {
                    "StringLike": {
                        "iam:AWSServiceName": [
                            "appmesh.amazonaws.com"
                        ]
                    }
                }
            },
            {
                "Effect": "Allow",
                "Action": [
                    "acm:ListCertificates",
                    "acm:DescribeCertificate",
                    "acm-pca:DescribeCertificateAuthority",
                    "acm-pca:ListCertificateAuthorities"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
        "servicediscovery:CreateService",
        "servicediscovery:DeleteService",
        "servicediscovery:GetService",
        "servicediscovery:GetInstance",
        "servicediscovery:RegisterInstance",
        "servicediscovery:DeregisterInstance",
        "servicediscovery:ListInstances",
        "servicediscovery:ListNamespaces",
        "servicediscovery:ListServices",
        "servicediscovery:GetInstancesHealthStatus",
        "servicediscovery:UpdateInstanceCustomHealthStatus",
        "servicediscovery:GetOperation",
        "route53:GetHealthCheck",
        "route53:CreateHealthCheck",
        "route53:UpdateHealthCheck",
        "route53:ChangeResourceRecordSets",
        "route53:DeleteHealthCheck"
                ],
                "Resource": "*"
            }
        ]
    }
    EOF
}

resource "helm_release" "appmesh-controller" {
  name       = "appmesh-controller"
  chart      = "appmesh-controller"
  repository = "https://aws.github.io/eks-charts"
  version    = "1.4.1"

  namespace       = "appmesh-system"
  cleanup_on_fail = "true"
  atomic          = "true"
  timeout         = 600

  values = [<<EOF
  region: ${local.region}
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: ${aws_iam_role.appmesh-controller.arn}
  EOF
  ]

  depends_on = [
    kubernetes_namespace.appmesh-system
  ]
}

resource "null_resource" "appmesh-label" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(module.eks.kubeconfig)
    }
    command = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) label namespace default meshes.appmesh.k8s.aws=default ;
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) label namespace default appmesh.k8s.aws/sidecarInjectorWebhook=enabled
    EOF
  }
  depends_on = [
    helm_release.appmesh-controller
  ]
}

# Until we can use terraform 0.14+, and thus be able to use kubernetes_manifest,
# we need to do this with kubectl.  :-(
data "template_file" "appmesh-default" {
  template = <<-EOF
apiVersion: appmesh.k8s.aws/v1beta2
kind: Mesh
metadata:
  name: default
spec:
  namespaceSelector:
    matchLabels:
      mesh: default
EOF
}

# This is actually what causes the mesh-controller to start up an app mesh.
resource "null_resource" "appmesh-default" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(module.eks.kubeconfig)
    }
    command = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) apply -f <(echo '${data.template_file.appmesh-default.rendered}') 
    EOF
  }
  depends_on = [
    null_resource.appmesh-label
  ]
}
