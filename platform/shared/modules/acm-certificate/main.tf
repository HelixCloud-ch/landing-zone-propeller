locals {
  effective_validation_method = var.certificate_authority_arn != null ? null : coalesce(var.validation_method, "DNS")
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = local.effective_validation_method
  certificate_authority_arn = var.certificate_authority_arn
  early_renewal_duration    = var.early_renewal_duration
  key_algorithm             = var.key_algorithm

  dynamic "validation_option" {
    for_each = var.validation_domains
    content {
      domain_name       = validation_option.key
      validation_domain = validation_option.value
    }
  }

  tags = merge({ Name = var.domain_name }, var.tags)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "this" {
  count = var.wait_for_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = length(var.validation_record_fqdns) > 0 ? var.validation_record_fqdns : null

  timeouts {
    create = var.validation_timeout
  }
}

locals {
  validation_options = local.effective_validation_method == "DNS" ? [
    for o in aws_acm_certificate.this.domain_validation_options : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ] : []

  # An apex and its wildcard share one record: group by name, keep the first.
  validation_by_name = { for o in local.validation_options : o.name => o... }

  validation_by_domain = local.effective_validation_method == "DNS" ? {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  } : {}
}
