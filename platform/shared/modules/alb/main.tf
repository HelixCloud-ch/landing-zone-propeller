resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_91: access logs are an optional input; the caller owns the log bucket and its policy.
  #checkov:skip=CKV2_AWS_28: the WAF web ACL is an optional input owned by the caller.
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = var.internal
  ip_address_type            = "ipv4"
  subnets                    = var.subnet_ids
  security_groups            = var.security_group_ids
  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection
  desync_mitigation_mode     = var.desync_mitigation_mode
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.access_logs == null ? [] : [var.access_logs]
    content {
      enabled = true
      bucket  = access_logs.value.bucket
      prefix  = access_logs.value.prefix
    }
  }

  dynamic "connection_logs" {
    for_each = var.connection_logs == null ? [] : [var.connection_logs]
    content {
      enabled = true
      bucket  = connection_logs.value.bucket
      prefix  = connection_logs.value.prefix
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_wafv2_web_acl_association" "this" {
  count        = var.web_acl_arn == null ? 0 : 1
  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.web_acl_arn
}
