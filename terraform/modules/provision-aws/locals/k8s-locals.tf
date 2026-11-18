locals {
  certificate_authority_data = module.eks.cluster_certificate_authority_data
  # persistent_storage_key_id  = aws_kms_key.ebs-key.key_id
  server        = module.eks.cluster_endpoint
  zone_id       = aws_route53_zone.cluster.zone_id
  zone_role_arn = aws_iam_role.external_dns.arn
  # launch_template_name       = data.aws_launch_template.eks_launch_template.name
  vpc_cidr_range = module.vpc.vpc_cidr_block
}
