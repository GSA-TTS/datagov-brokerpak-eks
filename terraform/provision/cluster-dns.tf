# -----------------------------------------------------------------
# SETUP DNS+DNSSEC for the cluster
# -----------------------------------------------------------------

# get externally configured DNS Zone 
data "aws_route53_zone" "zone" {
  name = local.base_domain
}

# Create hosted zone for cluster-specific subdomain name
resource "aws_route53_zone" "cluster" {
  name = local.domain
  # There may be extraneous DNS records from external-dns; that's expected.
  force_destroy = true
  tags = merge(var.labels, {
    Environment = local.cluster_name
    domain      = local.domain
  })
}

# Create the NS record in main domain hosted zone for sub domain hosted zone
resource "aws_route53_record" "cluster-ns" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = local.domain
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.cluster.name_servers
}

