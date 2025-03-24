# data "aws_vpc" "selected" {
#   id = var.vpc_id
# }

resource "aws_route53_zone" "private" {
  name = var.domain

  vpc {
    vpc_id = var.vpc_id
  }
}

resource "aws_route53_record" "vault" {
  zone_id = aws_route53_zone.private.zone_id
  name    = var.lb_fqdn
  type    = "A"
  alias {
    name                   = var.vault_lb_dns_name
    zone_id                = var.vault_lb_zone_id
    evaluate_target_health = true
  }
}