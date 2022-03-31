locals {
  autoscaler_policy = <<-POLICY
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Action": [
                  "autoscaling:DescribeAutoScalingGroups",
                  "autoscaling:DescribeAutoScalingInstances",
                  "autoscaling:DescribeLaunchConfigurations",
                  "autoscaling:DescribeTags",
                  "autoscaling:SetDesiredCapacity",
                  "autoscaling:TerminateInstanceInAutoScalingGroup",
                  "ec2:DescribeLaunchTemplateVersions"
              ],
              "Resource": "*",
              "Effect": "Allow"
          }
      ]
  }
  POLICY
}

resource "aws_iam_role_policy" "autoscaler-policy" {
  name_prefix = "${local.cluster_name}-autoscaler-policy"
  role        = aws_iam_role.iam_role_fargate.name
  policy      = local.autoscaler_policy
}

# resource "kubernetes_manifest" "cluster-autoscaler" {
#   # Original source: https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
#   manifest = yamldecode(replace(file("${path.module}/cluster-autoscaler-autodiscover.yaml"), "<YOUR CLUSTER NAME>", "${local.cluster_name}"))
# 
#   depends_on = [
#     null_resource.cluster-functional
#   ]
# }

# TODO: Update to use kubeneters provider when properly supported
# https://github.com/hashicorp/terraform-provider-kubernetes/issues/692
# For now, using null_resource
resource "null_resource" "cluster-autoscaler-setup" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(module.eks.kubeconfig)
      AUTOSCALER = replace(file("cluster-autoscaler-autodiscover.yaml"), "<YOUR CLUSTER NAME>", "${local.cluster_name}")
    }

    command = <<-EOF
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) apply -f - <<< "$AUTOSCALER"
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) annotate serviceaccount cluster-autoscaler \
        -n kube-system eks.amazonaws.com/role-arn=${aws_iam_role.iam_role_fargate.arn}
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) patch deployment cluster-autoscaler \
        -n kube-system -p '{"spec":{"template":{"metadata":{"annotations":{"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}}}}'
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) patch deployment cluster-autoscaler \
        -n kube-system -p '{"spec":{"containers":{"command":"--balance-similar-node-groups"}}}'
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) patch deployment cluster-autoscaler \
        -n kube-system -p '{"spec":{"containers":{"command":{"--skip-nodes-with-system-pods": "false"}}}}'
      kubectl --kubeconfig <(echo $KUBECONFIG | base64 -d) set image deployment cluster-autoscaler -n kube-system cluster-autoscaler=k8s.gcr.io/autoscaling/cluster-autoscaler:v1.19.1
    EOF
  }
  depends_on = [
    # kubernetes_manifest.cluster-autoscaler,
    null_resource.cluster-functional
  ]
}
