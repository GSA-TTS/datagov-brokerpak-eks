# This file contains the outputs necessary when the directory is
# used as a standalone module. Leave it out if you're combining this directory
# with the provision-k8s module.

output "persistent_storage_key_id" { value = aws_kms_key.ebs-key.key_id }
output "zone_id" { value = aws_route53_zone.cluster.zone_id }
output "zone_role_arn" { value = aws_iam_role.external_dns.arn }
# output "launch_template_name" { value = data.aws_launch_template.eks_launch_template.name }
