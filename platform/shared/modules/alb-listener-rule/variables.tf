variable "listener_arn" {
  type        = string
  description = "ARN of the listener that holds the rule."
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:.*:listener/", var.listener_arn))
    error_message = "listener_arn must be a listener ARN."
  }
}

variable "priority" {
  type        = number
  description = "Rule priority (1-50000), unique per listener. Lower values are evaluated first."
  validation {
    condition     = var.priority == floor(var.priority) && var.priority >= 1 && var.priority <= 50000
    error_message = "priority must be an integer between 1 and 50000."
  }
}

variable "name" {
  type        = string
  description = "Value of the Name tag. Null sets no Name tag."
  default     = null
}

variable "conditions" {
  type = object({
    host_headers         = optional(list(string), [])
    path_patterns        = optional(list(string), [])
    http_request_methods = optional(list(string), [])
    source_ips           = optional(list(string), [])
    http_headers         = optional(list(object({ name = string, values = list(string) })), [])
    query_strings        = optional(list(object({ key = optional(string), value = string })), [])
  })
  description = "Match conditions. All non-empty groups must match. At least one is required."

  validation {
    condition = (
      length(var.conditions.host_headers) + length(var.conditions.path_patterns) +
      length(var.conditions.http_request_methods) + length(var.conditions.source_ips) +
      length(var.conditions.http_headers) + length(var.conditions.query_strings)
    ) > 0
    error_message = "conditions must set at least one condition."
  }
  validation {
    condition = (
      length(var.conditions.host_headers) + length(var.conditions.path_patterns) +
      length(var.conditions.http_request_methods) + length(var.conditions.source_ips) +
      length(var.conditions.query_strings) + sum(concat([0], [for h in var.conditions.http_headers : length(h.values)]))
    ) <= 5
    error_message = "A rule allows at most five match evaluations (condition values) in total."
  }
  validation {
    condition     = alltrue([for p in concat(var.conditions.host_headers, var.conditions.path_patterns) : length(p) <= 128])
    error_message = "Each host header and path pattern must have at most 128 characters."
  }
  validation {
    condition     = alltrue([for m in var.conditions.http_request_methods : can(regex("^[A-Z_-]{1,40}$", m))])
    error_message = "Each HTTP request method must be 1-40 upper-case letters, hyphens or underscores."
  }
  validation {
    condition     = alltrue([for c in var.conditions.source_ips : can(cidrnetmask(c))])
    error_message = "Each source IP must be a valid IPv4 CIDR block."
  }
  validation {
    condition = alltrue([
      for h in var.conditions.http_headers : length(h.name) >= 1 && length(h.name) <= 40 && lower(h.name) != "host"
    ])
    error_message = "Each HTTP header name must have 1-40 characters and must not be Host (use host_headers)."
  }
}

variable "action" {
  type = object({
    type             = string
    target_group_arn = optional(string)
    redirect = optional(object({
      status_code = optional(string, "HTTP_301")
      protocol    = optional(string)
      host        = optional(string)
      port        = optional(string)
      path        = optional(string)
      query       = optional(string)
    }))
    fixed_response = optional(object({
      status_code  = string
      content_type = optional(string, "text/plain")
      message_body = optional(string)
    }))
  })
  description = "Rule action: forward, redirect or fixed-response. See README for the rules."

  validation {
    condition     = contains(["forward", "redirect", "fixed-response"], var.action.type)
    error_message = "action.type must be forward, redirect or fixed-response."
  }
  validation {
    condition = var.action.type != "forward" || (
      var.action.target_group_arn != null &&
      var.action.redirect == null &&
      var.action.fixed_response == null
    )
    error_message = "A forward action needs target_group_arn and no redirect or fixed_response."
  }
  validation {
    condition = var.action.type != "redirect" || try(
      var.action.redirect != null &&
      var.action.target_group_arn == null &&
      var.action.fixed_response == null &&
      contains(["HTTP_301", "HTTP_302"], var.action.redirect.status_code) &&
      contains(["HTTP", "HTTPS", "#{protocol}"], coalesce(var.action.redirect.protocol, "HTTP")) &&
      startswith(coalesce(var.action.redirect.path, "/"), "/"),
      false
    )
    error_message = "A redirect action needs a redirect block only, status HTTP_301 or HTTP_302, protocol HTTP, HTTPS or #{protocol}, and a path that starts with a slash."
  }
  validation {
    condition = var.action.type != "fixed-response" || try(
      var.action.fixed_response != null &&
      var.action.target_group_arn == null &&
      var.action.redirect == null &&
      can(regex("^[245][0-9]{2}$", var.action.fixed_response.status_code)) &&
      contains(["text/plain", "text/css", "text/html", "application/javascript", "application/json"], var.action.fixed_response.content_type),
      false
    )
    error_message = "A fixed-response action needs a fixed_response block only, a 2XX, 4XX or 5XX status code, and a supported content type."
  }
  validation {
    condition     = var.action.target_group_arn == null || can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/.+", var.action.target_group_arn))
    error_message = "action.target_group_arn must be a target group ARN."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags for the rule."
  default     = {}
}
