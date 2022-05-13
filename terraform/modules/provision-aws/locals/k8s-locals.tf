locals {
  certificate_authority_data = data.aws_eks_cluster.main.certificate_authority[0].data
  persistent_storage_key_id  = aws_kms_key.ebs-key.key_id
  server                     = data.aws_eks_cluster.main.endpoint
  zone_id                    = aws_route53_zone.cluster.zone_id
  zone_role_arn              = aws_iam_role.external_dns.arn
  launch_template_name       = data.aws_launch_template.eks_launch_template.id
  vpc_cidr_range             = module.vpc.vpc_cidr_block
}
