variable "load_balancer_arn" {
  type        = string
  description = "ARN of the load balancer."
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:", var.load_balancer_arn))
    error_message = "load_balancer_arn must be an Elastic Load Balancing ARN."
  }
}

variable "port" {
  type        = number
  description = "Listener port."
  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "port must be between 1 and 65535."
  }
}

variable "protocol" {
  type        = string
  description = "Listener protocol: HTTP or HTTPS."
  validation {
    condition     = contains(["HTTP", "HTTPS"], var.protocol)
    error_message = "protocol must be HTTP or HTTPS."
  }
}

variable "certificate_arns" {
  type        = list(string)
  description = "ACM or IAM certificate ARNs. The first is the default. Required for HTTPS, empty for HTTP."
  default     = []
  validation {
    condition     = var.protocol == "HTTPS" ? length(var.certificate_arns) >= 1 : length(var.certificate_arns) == 0
    error_message = "An HTTPS listener needs at least one certificate; an HTTP listener takes none."
  }
  validation {
    condition = alltrue([
      for c in var.certificate_arns :
      can(regex("^arn:aws[a-z-]*:(acm:[a-z0-9-]+:[0-9]{12}:certificate/.+|iam::[0-9]{12}:server-certificate/.+)$", c))
    ])
    error_message = "Each certificate must be an ACM certificate ARN or an IAM server certificate ARN."
  }
  validation {
    condition     = length(distinct(var.certificate_arns)) == length(var.certificate_arns)
    error_message = "certificate_arns must not contain duplicates."
  }
}

variable "ssl_policy" {
  type        = string
  description = "TLS security policy for HTTPS (TLS 1.2 minimum). Ignored for HTTP."
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  nullable    = false
  validation {
    condition     = can(regex("^ELBSecurityPolicy-TLS13-1-[23]-", var.ssl_policy))
    error_message = "ssl_policy must be a TLS13-1-2 or TLS13-1-3 policy, so that TLS 1.2 is the minimum version."
  }
}

variable "allow_plain_http" {
  type        = bool
  description = "Allow an HTTP listener that does not redirect to HTTPS."
  default     = false
}

variable "default_action" {
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
  description = "Default action: forward, redirect or fixed-response. See README for the rules."

  validation {
    condition     = contains(["forward", "redirect", "fixed-response"], var.default_action.type)
    error_message = "default_action.type must be forward, redirect or fixed-response."
  }
  validation {
    condition = var.default_action.type != "forward" || (
      var.default_action.target_group_arn != null &&
      var.default_action.redirect == null &&
      var.default_action.fixed_response == null
    )
    error_message = "A forward action needs target_group_arn and no redirect or fixed_response."
  }
  validation {
    condition = var.default_action.type != "redirect" || try(
      var.default_action.redirect != null &&
      var.default_action.target_group_arn == null &&
      var.default_action.fixed_response == null &&
      contains(["HTTP_301", "HTTP_302"], var.default_action.redirect.status_code) &&
      contains(["HTTP", "HTTPS", "#{protocol}"], coalesce(var.default_action.redirect.protocol, "HTTP")) &&
      startswith(coalesce(var.default_action.redirect.path, "/"), "/"),
      false
    )
    error_message = "A redirect action needs a redirect block only, status HTTP_301 or HTTP_302, protocol HTTP, HTTPS or #{protocol}, and a path that starts with a slash."
  }
  validation {
    condition = var.default_action.type != "fixed-response" || try(
      var.default_action.fixed_response != null &&
      var.default_action.target_group_arn == null &&
      var.default_action.redirect == null &&
      can(regex("^[245][0-9]{2}$", var.default_action.fixed_response.status_code)) &&
      contains(["text/plain", "text/css", "text/html", "application/javascript", "application/json"], var.default_action.fixed_response.content_type),
      false
    )
    error_message = "A fixed-response action needs a fixed_response block only, a 2XX, 4XX or 5XX status code, and a supported content type."
  }
  validation {
    condition     = var.default_action.target_group_arn == null || can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/.+", var.default_action.target_group_arn))
    error_message = "default_action.target_group_arn must be a target group ARN."
  }
  validation {
    condition = var.protocol != "HTTP" || var.allow_plain_http || try(
      var.default_action.type == "redirect" && var.default_action.redirect.protocol == "HTTPS",
      false
    )
    error_message = "An HTTP listener must redirect to HTTPS unless allow_plain_http is true."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags for the listener."
  default     = {}
}
