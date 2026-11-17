locals {
  validation_zone_ids = toset([for c in values(var.certificates) : c.validation_zone_id if c.validation_zone_id != null])

  record_entries = flatten([
    for k, c in var.certificates : [
      for n in concat([c.domain_name], c.subject_alternative_names) : {
        cert = k
        name = n
        zone = c.validation_zone_id
        key  = "${c.validation_zone_id}|${trimprefix(n, "*.")}"
      }
    ] if c.validation_zone_id != null
  ])

  record_sources = { for e in local.record_entries : e.key => e... }

  created_record_fqdns = {
    for k, c in var.certificates : k => distinct([
      for e in local.record_entries : module.validation_record[e.key].fqdn if e.cert == k
    ])
  }

  validation_records = merge([
    for cert in module.certificate : {
      for r in cert.validation_records :
      "acm-${substr(sha1(r.name), 0, 8)}" => {
        name    = r.name
        type    = "CNAME"
        ttl     = 300
        records = [r.value]
      }
    }
  ]...)
}
