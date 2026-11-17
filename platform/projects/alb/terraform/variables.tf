variable "region" {
  type        = string
  description = "AWS region."
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must look like eu-central-2."
  }
}

variable "name" {
  type        = string
  description = "Load balancer name. Prefix of the security group and default target group names."
}

variable "internal" {
  type        = bool
  description = "Create an internal (private) load balancer."
  default     = true
}

variable "vpc_id" {
  type        = string
  description = "VPC ID of the load balancer and the target groups."
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "At least two subnet IDs in different Availability Zones."
}

variable "create_security_group" {
  type        = bool
  description = "Create a security group for the load balancer. See README for the modes."
  default     = true
}

variable "security_group_ids" {
  type        = list(string)
  description = "Existing security group IDs to attach. Required when create_security_group is false."
  default     = []
  validation {
    condition     = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", s))]) && length(distinct(var.security_group_ids)) == length(var.security_group_ids)
    error_message = "security_group_ids must hold unique security group IDs (sg-...)."
  }
  validation {
    condition     = var.create_security_group || length(var.security_group_ids) > 0
    error_message = "security_group_ids must not be empty when create_security_group is false."
  }
}

variable "security_group_ingress_cidrs" {
  type        = list(string)
  description = "IPv4 CIDRs allowed to reach the listener ports of the created security group."
  default     = []
  validation {
    condition     = alltrue([for c in var.security_group_ingress_cidrs : can(cidrnetmask(c))])
    error_message = "Each ingress CIDR must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = !var.create_security_group || length(var.security_group_ingress_cidrs) > 0
    error_message = "security_group_ingress_cidrs must not be empty when create_security_group is true."
  }
  validation {
    condition     = !var.internal || !contains(var.security_group_ingress_cidrs, "0.0.0.0/0")
    error_message = "An internal load balancer must not allow 0.0.0.0/0 as an ingress CIDR."
  }
}

variable "security_group_egress_cidrs" {
  type        = list(string)
  description = "IPv4 CIDRs the created security group may reach. Empty uses the VPC CIDR."
  default     = []
  validation {
    condition     = alltrue([for c in var.security_group_egress_cidrs : can(cidrnetmask(c))])
    error_message = "Each egress CIDR must be a valid IPv4 CIDR block."
  }
}

variable "security_group_egress_ports" {
  type        = list(number)
  description = "Extra egress ports of the created security group, e.g. for target groups owned elsewhere."
  default     = []
  validation {
    condition     = alltrue([for p in var.security_group_egress_ports : p >= 1 && p <= 65535 && floor(p) == p])
    error_message = "Each egress port must be an integer from 1 to 65535."
  }
}

variable "certificate_arns" {
  type        = map(string)
  description = "ACM certificate ARNs by key. Listeners refer to the keys."
  default     = {}
  validation {
    condition     = alltrue([for a in values(var.certificate_arns) : can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/.+$", a))])
    error_message = "Each certificate ARN must be an ACM certificate ARN."
  }
}

variable "ip_target_groups" {
  type = map(object({
    name                     = optional(string)
    port                     = optional(number, 443)
    protocol                 = optional(string, "HTTPS")
    protocol_version         = optional(string)
    deregistration_delay     = optional(number)
    target_ips               = optional(list(string), [])
    target_availability_zone = optional(string)
    health_check = optional(object({
      protocol            = optional(string)
      port                = optional(string)
      path                = optional(string)
      matcher             = optional(string)
      interval            = optional(number)
      timeout             = optional(number)
      healthy_threshold   = optional(number)
      unhealthy_threshold = optional(number)
    }), {})
  }))
  description = <<-EOT
    Target groups of type ip, by key. The key is the state address.
    Name defaults to "<name>-<key>". See README for the fields.
  EOT
  default     = {}
  validation {
    condition     = alltrue([for k in keys(var.ip_target_groups) : can(regex("^[a-z0-9-]{1,32}$", k))])
    error_message = "Target group keys must match ^[a-z0-9-]{1,32}$."
  }
  validation {
    condition = (
      length(distinct([for k, v in var.ip_target_groups : v.name != null ? v.name : "${var.name}-${k}"])) == length(var.ip_target_groups) &&
      alltrue([for k, v in var.ip_target_groups : length(v.name != null ? v.name : "${var.name}-${k}") <= 32])
    )
    error_message = "Target group names must be unique and at most 32 characters."
  }
}

variable "target_ips_by_group" {
  type        = map(list(string))
  description = "Target IPs by ip_target_groups key. A list replaces target_ips of that group."
  default     = {}
  validation {
    condition     = alltrue([for k in keys(var.target_ips_by_group) : contains(keys(var.ip_target_groups), k)])
    error_message = "Every key of target_ips_by_group must exist in ip_target_groups."
  }
}

variable "existing_target_group_arns" {
  type        = map(string)
  description = "ARNs of target groups owned elsewhere, by key. Actions refer to the keys. See README for target groups owned elsewhere."
  default     = {}
  validation {
    condition     = alltrue([for k in keys(var.existing_target_group_arns) : can(regex("^[a-z0-9-]{1,32}$", k))])
    error_message = "existing_target_group_arns keys must match ^[a-z0-9-]{1,32}$."
  }
  validation {
    condition     = alltrue([for a in values(var.existing_target_group_arns) : can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/.+$", a))])
    error_message = "Each value of existing_target_group_arns must be a target group ARN."
  }
  validation {
    condition     = length(setintersection(keys(var.existing_target_group_arns), keys(var.ip_target_groups))) == 0
    error_message = "A key must not be in both existing_target_group_arns and ip_target_groups."
  }
}

variable "listeners" {
  type = map(object({
    port             = number
    protocol         = string
    certificate_keys = optional(list(string), [])
    ssl_policy       = optional(string)
    allow_plain_http = optional(bool, false)
    default_action = object({
      type             = string
      target_group_key = optional(string)
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
  }))
  description = <<-EOT
    Listeners by key. The key is the state address.
    certificate_keys refer to certificate_arns. See README for the fields.
  EOT
  default     = {}
  validation {
    condition     = alltrue([for k in keys(var.listeners) : can(regex("^[a-z0-9-]{1,32}$", k))])
    error_message = "Listener keys must match ^[a-z0-9-]{1,32}$."
  }
  validation {
    condition = alltrue([
      for l in values(var.listeners) :
      l.default_action.target_group_key == null || contains(concat(keys(var.ip_target_groups), keys(var.existing_target_group_arns)), coalesce(l.default_action.target_group_key, ""))
    ])
    error_message = "Every target_group_key in a listener default_action must exist in ip_target_groups or existing_target_group_arns."
  }
  validation {
    condition     = alltrue([for l in values(var.listeners) : alltrue([for c in l.certificate_keys : contains(keys(var.certificate_arns), c)])])
    error_message = "Every certificate key of a listener must exist in certificate_arns."
  }
  validation {
    condition     = length(distinct([for l in values(var.listeners) : l.port])) == length(var.listeners)
    error_message = "Listener ports must be unique."
  }
}

variable "listener_rules" {
  type = map(object({
    listener_key = string
    priority     = number
    name         = optional(string)
    conditions = object({
      host_headers         = optional(list(string), [])
      path_patterns        = optional(list(string), [])
      http_request_methods = optional(list(string), [])
      source_ips           = optional(list(string), [])
      http_headers         = optional(list(object({ name = string, values = list(string) })), [])
      query_strings        = optional(list(object({ key = optional(string), value = string })), [])
    })
    action = object({
      type             = string
      target_group_key = optional(string)
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
  }))
  description = <<-EOT
    Listener rules by key. The key is the state address; the order comes only
    from priority, unique per listener. See README for the fields.
  EOT
  default     = {}
  validation {
    condition     = alltrue([for k in keys(var.listener_rules) : can(regex("^[a-z0-9-]{1,32}$", k))])
    error_message = "Listener rule keys must match ^[a-z0-9-]{1,32}$."
  }
  validation {
    condition     = alltrue([for r in values(var.listener_rules) : contains(keys(var.listeners), r.listener_key)])
    error_message = "Every listener_key of a rule must exist in listeners."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) :
      r.action.target_group_key == null || contains(concat(keys(var.ip_target_groups), keys(var.existing_target_group_arns)), coalesce(r.action.target_group_key, ""))
    ])
    error_message = "Every target_group_key in a rule action must exist in ip_target_groups or existing_target_group_arns."
  }
  validation {
    condition     = length(distinct([for r in values(var.listener_rules) : "${r.listener_key}:${r.priority}"])) == length(var.listener_rules)
    error_message = "The pair listener_key and priority must be unique."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) :
      r.action.type != "forward" || try(var.listeners[r.listener_key].protocol == "HTTPS" || var.listeners[r.listener_key].allow_plain_http, true)
    ])
    error_message = "A forward rule on an HTTP listener needs allow_plain_http = true on that listener."
  }
}

variable "idle_timeout" {
  type        = number
  description = "Idle timeout in seconds (1-4000)."
  default     = 60
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Block deletion of the load balancer. Set to false before destroy or sleep."
  default     = true
}

variable "desync_mitigation_mode" {
  type        = string
  description = "Desync mitigation mode: monitor, defensive or strictest."
  default     = "defensive"
}

variable "access_logs" {
  type = object({
    bucket = string
    prefix = optional(string)
  })
  description = "S3 bucket for access logs. Null disables them."
  default     = null
}

variable "connection_logs" {
  type = object({
    bucket = string
    prefix = optional(string)
  })
  description = "S3 bucket for connection logs. Null disables them."
  default     = null
}

variable "web_acl_arn" {
  type        = string
  description = "WAFv2 web ACL ARN to associate. Null skips the association."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Per-project tags."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Pipeline-wide tags."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Framework-managed tags."
  default     = {}
}
