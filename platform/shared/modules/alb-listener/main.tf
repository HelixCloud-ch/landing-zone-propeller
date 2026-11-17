resource "aws_lb_listener" "this" {
  #checkov:skip=CKV_AWS_2: protocol is an input; HTTP is only allowed as a redirect to HTTPS unless allow_plain_http is set.
  #checkov:skip=CKV_AWS_103: ssl_policy must be a TLS 1.2 minimum policy (variable validation).
  #checkov:skip=CKV2_AWS_20: HTTP listeners are validated to redirect to HTTPS unless allow_plain_http is set.
  load_balancer_arn = var.load_balancer_arn
  port              = var.port
  protocol          = var.protocol
  ssl_policy        = var.protocol == "HTTPS" ? var.ssl_policy : null
  certificate_arn   = var.protocol == "HTTPS" ? try(var.certificate_arns[0], null) : null

  default_action {
    type             = var.default_action.type
    target_group_arn = var.default_action.type == "forward" ? var.default_action.target_group_arn : null

    dynamic "redirect" {
      for_each = var.default_action.redirect == null ? [] : [var.default_action.redirect]
      content {
        status_code = redirect.value.status_code
        protocol    = redirect.value.protocol
        host        = redirect.value.host
        port        = redirect.value.port
        path        = redirect.value.path
        query       = redirect.value.query
      }
    }

    dynamic "fixed_response" {
      for_each = var.default_action.fixed_response == null ? [] : [var.default_action.fixed_response]
      content {
        status_code  = fixed_response.value.status_code
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
      }
    }
  }

  tags = var.tags
}

resource "aws_lb_listener_certificate" "this" {
  for_each        = toset(slice(var.certificate_arns, min(1, length(var.certificate_arns)), length(var.certificate_arns)))
  listener_arn    = aws_lb_listener.this.arn
  certificate_arn = each.value
}
