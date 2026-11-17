variable "name" {
  type        = string
  description = "Load balancer name (1-32 characters: letters, digits, hyphens; must not start with internal-)."
  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 1-32 characters of letters, digits and hyphens, must not start or end with a hyphen, and must not start with internal-."
  }
}

variable "internal" {
  type        = bool
  description = "Create an internal (private) load balancer."
  default     = true
}

variable "subnet_ids" {
  type        = list(string)
  description = "At least two subnet IDs in different Availability Zones."
  validation {
    condition = (
      length(var.subnet_ids) >= 2 &&
      alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))]) &&
      length(distinct(var.subnet_ids)) == length(var.subnet_ids)
    )
    error_message = "subnet_ids must hold at least two unique subnet IDs (subnet-...)."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs to attach (at least one)."
  validation {
    condition     = length(var.security_group_ids) >= 1 && alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", s))])
    error_message = "security_group_ids must hold at least one security group ID (sg-...)."
  }
}

variable "idle_timeout" {
  type        = number
  description = "Idle timeout in seconds (1-4000)."
  default     = 60
  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Block deletion of the load balancer. Set to false before destroy."
  default     = true
}

variable "desync_mitigation_mode" {
  type        = string
  description = "Desync mitigation mode: monitor, defensive or strictest."
  default     = "defensive"
  validation {
    condition     = contains(["monitor", "defensive", "strictest"], var.desync_mitigation_mode)
    error_message = "desync_mitigation_mode must be monitor, defensive or strictest."
  }
}

variable "access_logs" {
  type = object({
    bucket = string
    prefix = optional(string)
  })
  description = "S3 bucket for access logs. Null disables them. The caller owns the bucket policy."
  default     = null
  validation {
    condition     = var.access_logs == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_logs.bucket))
    error_message = "access_logs.bucket must be a valid S3 bucket name."
  }
}

variable "connection_logs" {
  type = object({
    bucket = string
    prefix = optional(string)
  })
  description = "S3 bucket for connection logs. Null disables them. The caller owns the bucket policy."
  default     = null
  validation {
    condition     = var.connection_logs == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.connection_logs.bucket))
    error_message = "connection_logs.bucket must be a valid S3 bucket name."
  }
}

variable "web_acl_arn" {
  type        = string
  description = "WAFv2 web ACL ARN to associate. Null skips the association."
  default     = null
  validation {
    condition     = var.web_acl_arn == null || can(regex("^arn:aws[a-z-]*:wafv2:", var.web_acl_arn))
    error_message = "web_acl_arn must be null or a WAFv2 web ACL ARN."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags for the load balancer. The Name tag is set to name."
  default     = {}
}
