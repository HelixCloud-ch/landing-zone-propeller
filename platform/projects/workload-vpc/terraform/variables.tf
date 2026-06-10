variable "region" {
  type        = string
  description = "AWS region the workload VPC is created in (must match the landing-zone home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "az_count" {
  type        = number
  description = "Number of Availability Zones the subnet tiers span, bounded by the AZs available in the region."
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "az_count must be between 1 and 6 inclusive."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block for the workload VPC. Must be a valid IPv4 CIDR (e.g. 10.16.0.0/24) and must not overlap any other allocated block in the landing-zone CIDR plan."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.16.0.0/24)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of every resource (e.g. \"test1-vpc\" yields \"test1-vpc-vpc\", \"test1-vpc-app-rt\")."
  default     = "test1-vpc"

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
    subnet per Availability Zone. Per tier, CIDRs come from an explicit `cidrs`
    list (one per AZ) when set, otherwise they are derived from vpc_cidr via
    cidrsubnet(vpc_cidr, newbits, netnum_base + az_index). Provide either
    `cidrs` or both `newbits` and `netnum_base`.

    extra_tags: additional tags merged onto every subnet in the tier on top of
    the provider default_tags. Typical use: controller-discovery tags for
    Kubernetes load-balancer controllers, e.g.
      "kubernetes.io/role/internal-elb" = "1"
      "kubernetes.io/cluster/<cluster-name>" = "shared"
  EOT
}

variable "tgw_id" {
  type        = string
  description = "ID of the RAM-shared landing-zone Transit Gateway, delivered via @landing-zone/workload-parameters.tgw_id."

  validation {
    condition     = can(regex("^tgw-[0-9a-f]+$", var.tgw_id))
    error_message = "tgw_id must be a valid Transit Gateway ID (tgw-...)."
  }
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
