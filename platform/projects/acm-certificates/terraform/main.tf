module "certificate" {
  source   = "../../../shared/modules/acm-certificate"
  for_each = var.certificates

  domain_name               = each.value.domain_name
  subject_alternative_names = each.value.subject_alternative_names
  validation_method         = each.value.validation_method
  validation_domains        = each.value.validation_domains
  certificate_authority_arn = each.value.certificate_authority_arn
  early_renewal_duration    = each.value.early_renewal_duration
  key_algorithm             = each.value.key_algorithm
}

# The wait lives here, not in the module: with the waiter inside the module, terraform
# reports "Error: Cycle" (module.certificate output arn -> waiter -> record fqdns -> record
# name -> module.certificate). Confirmed with terraform validate on this project.
resource "aws_acm_certificate_validation" "this" {
  for_each = { for k, c in var.certificates : k => c if c.wait_for_validation }

  certificate_arn         = module.certificate[each.key].arn
  validation_record_fqdns = length(local.created_record_fqdns[each.key]) > 0 ? local.created_record_fqdns[each.key] : null

  timeouts {
    create = var.validation_timeout
  }
}

data "aws_route53_zone" "validation" {
  for_each = local.validation_zone_ids

  zone_id = each.key

  lifecycle {
    postcondition {
      condition     = self.private_zone != true
      error_message = "Hosted zone ${each.key} is private. ACM cannot validate through a private zone."
    }
  }
}

module "validation_record" {
  source   = "../../../shared/modules/dns-record"
  for_each = local.record_sources

  zone_id = each.value[0].zone
  name    = module.certificate[each.value[0].cert].validation_records_by_domain[each.value[0].name].name
  type    = "CNAME"
  ttl     = 300
  records = [module.certificate[each.value[0].cert].validation_records_by_domain[each.value[0].name].value]

  depends_on = [data.aws_route53_zone.validation]
}
