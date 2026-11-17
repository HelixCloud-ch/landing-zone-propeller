resource "aws_lb_listener_rule" "this" {
  listener_arn = var.listener_arn
  priority     = var.priority

  action {
    type             = var.action.type
    target_group_arn = var.action.type == "forward" ? var.action.target_group_arn : null

    dynamic "redirect" {
      for_each = var.action.redirect == null ? [] : [var.action.redirect]
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
      for_each = var.action.fixed_response == null ? [] : [var.action.fixed_response]
      content {
        status_code  = fixed_response.value.status_code
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.conditions.host_headers) == 0 ? [] : [var.conditions.host_headers]
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.conditions.path_patterns) == 0 ? [] : [var.conditions.path_patterns]
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.conditions.http_request_methods) == 0 ? [] : [var.conditions.http_request_methods]
    content {
      http_request_method {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.conditions.source_ips) == 0 ? [] : [var.conditions.source_ips]
    content {
      source_ip {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = var.conditions.http_headers
    content {
      http_header {
        http_header_name = condition.value.name
        values           = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.conditions.query_strings) == 0 ? [] : [var.conditions.query_strings]
    content {
      dynamic "query_string" {
        for_each = condition.value
        content {
          key   = query_string.value.key
          value = query_string.value.value
        }
      }
    }
  }

  tags = merge(var.tags, var.name == null ? {} : { Name = var.name })
}
