variable "name" {
  type        = string
  description = "Target group name (1-32 characters: letters, digits, hyphens)."
  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", var.name))
    error_message = "name must be 1-32 characters of letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID of the target group."
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "port" {
  type        = number
  description = "Default port of the targets."
  default     = 443
  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "port must be between 1 and 65535."
  }
}

variable "protocol" {
  type        = string
  description = "Protocol to the targets: HTTP or HTTPS."
  default     = "HTTPS"
  validation {
    condition     = contains(["HTTP", "HTTPS"], var.protocol)
    error_message = "protocol must be HTTP or HTTPS."
  }
}

variable "protocol_version" {
  type        = string
  description = "Protocol version: HTTP1, HTTP2 or GRPC. Null uses the AWS default."
  default     = null
  validation {
    condition     = var.protocol_version == null || contains(["HTTP1", "HTTP2", "GRPC"], coalesce(var.protocol_version, "HTTP1"))
    error_message = "protocol_version must be null, HTTP1, HTTP2 or GRPC."
  }
}

variable "deregistration_delay" {
  type        = number
  description = "Seconds before a deregistering target is removed (0-3600). Null uses the AWS default."
  default     = null
  validation {
    condition     = var.deregistration_delay == null || (coalesce(var.deregistration_delay, 0) >= 0 && coalesce(var.deregistration_delay, 0) <= 3600)
    error_message = "deregistration_delay must be null or between 0 and 3600 seconds."
  }
}

variable "health_check" {
  type = object({
    protocol            = optional(string)
    port                = optional(string)
    path                = optional(string)
    matcher             = optional(string)
    interval            = optional(number)
    timeout             = optional(number)
    healthy_threshold   = optional(number)
    unhealthy_threshold = optional(number)
  })
  description = "Health check settings. Null fields use the AWS defaults, except protocol, which follows the target group."
  default     = {}

  validation {
    condition     = contains(["HTTP", "HTTPS"], coalesce(var.health_check.protocol, "HTTP"))
    error_message = "health_check.protocol must be null, HTTP or HTTPS."
  }
  validation {
    condition = (
      coalesce(var.health_check.port, "traffic-port") == "traffic-port" ||
      try(can(regex("^[0-9]{1,5}$", var.health_check.port)) && tonumber(var.health_check.port) >= 1 && tonumber(var.health_check.port) <= 65535, false)
    )
    error_message = "health_check.port must be null, traffic-port or a port number between 1 and 65535."
  }
  validation {
    condition     = can(regex("^/", coalesce(var.health_check.path, "/")))
    error_message = "health_check.path must start with a slash."
  }
  validation {
    condition     = can(regex("^[2-4][0-9]{2}(-[2-4][0-9]{2})?(,[2-4][0-9]{2}(-[2-4][0-9]{2})?)*$", coalesce(var.health_check.matcher, "200")))
    error_message = "health_check.matcher must be HTTP codes 200-499, as a list or ranges such as 200,404 or 200-399."
  }
  validation {
    condition     = coalesce(var.health_check.interval, 30) >= 5 && coalesce(var.health_check.interval, 30) <= 300
    error_message = "health_check.interval must be between 5 and 300 seconds."
  }
  validation {
    condition     = coalesce(var.health_check.timeout, 5) >= 2 && coalesce(var.health_check.timeout, 5) <= 120
    error_message = "health_check.timeout must be between 2 and 120 seconds."
  }
  validation {
    condition     = coalesce(var.health_check.healthy_threshold, 5) >= 2 && coalesce(var.health_check.healthy_threshold, 5) <= 10
    error_message = "health_check.healthy_threshold must be between 2 and 10."
  }
  validation {
    condition     = coalesce(var.health_check.unhealthy_threshold, 2) >= 2 && coalesce(var.health_check.unhealthy_threshold, 2) <= 10
    error_message = "health_check.unhealthy_threshold must be between 2 and 10."
  }
}

variable "target_ips" {
  type        = list(string)
  description = "Private IPv4 targets (RFC 1918 or 100.64.0.0/10), unique. Empty creates no attachments."
  default     = []
  validation {
    condition = alltrue([
      for ip in var.target_ips :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) &&
      anytrue([
        for c in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"] :
        try(cidrhost("${ip}/${split("/", c)[1]}", 0) == split("/", c)[0], false)
      ])
    ])
    error_message = "Each target IP must be an IPv4 address in 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 or 100.64.0.0/10."
  }
  validation {
    condition     = length(distinct(var.target_ips)) == length(var.target_ips)
    error_message = "target_ips must not contain duplicates."
  }
}

variable "target_availability_zone" {
  type        = string
  description = "AZ of the targets, or all for IPs outside the VPC. Null lets AWS derive it."
  default     = null
  validation {
    condition     = var.target_availability_zone == null || can(regex("^(all|[a-z]{2}(-[a-z]+)+-[0-9][a-z])$", coalesce(var.target_availability_zone, "all")))
    error_message = "target_availability_zone must be null, all or an Availability Zone name."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags for the target group. The Name tag is set to name."
  default     = {}
}
