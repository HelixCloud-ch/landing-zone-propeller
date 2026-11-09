module "dns_record" {
  source   = "../../../shared/modules/dns-record"
  for_each = var.records

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
  alias   = each.value.alias
}
