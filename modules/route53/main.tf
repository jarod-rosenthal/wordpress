# Lookup Hosted Zones for each domain
data "aws_route53_zone" "domain_zones" {
  count = length(var.domain_names)
  name  = var.domain_names[count.index]
}

# Create A Records for www subdomain
resource "aws_route53_record" "www" {
  count   = length(var.domain_names)
  zone_id = data.aws_route53_zone.domain_zones[count.index].zone_id
  name    = "www.${var.domain_names[count.index]}"
  type    = "A"
  ttl     = "300"
  records = [var.public_ips[count.index]]
  lifecycle {
    ignore_changes = [
      zone_id
    ]
  }
}

# Create A Records for root domain
resource "aws_route53_record" "root" {
  count   = length(var.domain_names)
  zone_id = data.aws_route53_zone.domain_zones[count.index].zone_id
  name    = var.domain_names[count.index]
  type    = "A"
  ttl     = "300"
  records = [var.public_ips[count.index]]
  lifecycle {
    ignore_changes = [
      zone_id
    ]
  }
}
