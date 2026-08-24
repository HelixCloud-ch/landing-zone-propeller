variable "region" {
  type        = string
  description = "AWS region the VPC is created in."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "az_count" {
  type        = number
  description = "Number of Availability Zones the subnet tiers span."
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "az_count must be between 1 and 6 inclusive."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block for the VPC."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.0.16.0/20)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of every resource."

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}

variable "tiers" {
  type = map(object({
    enabled                 = bool
    cidrs                   = optional(list(string))
    newbits                 = optional(number)
    netnum_base             = optional(number)
    map_public_ip_on_launch = optional(bool, false)
    extra_tags              = optional(map(string), {})
  }))
  description = <<-EOT
    Map of subnet tier name to its configuration. Enabled tiers create one
    subnet per AZ. CIDRs come from an explicit list or are derived via
    cidrsubnet(vpc_cidr, newbits, netnum_base + az_index).
  EOT
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Per-project tags applied to all resources via provider default_tags."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Pipeline-wide tags applied to all resources via provider default_tags."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Framework-managed tags applied to all resources via provider default_tags."
  default     = {}
}
