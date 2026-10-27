module "dns_record" {
  source = "../../../shared/modules/dns-record"

  zone_id = var.zone_id
  name    = var.name
  type    = var.type
  ttl     = var.ttl
  records = var.records
  alias   = var.alias
}
