variable "region" {
  type        = string
  description = "AWS region for the hub VPC (must match the Control Tower home region)."

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
  description = "IPv4 CIDR block for the hub VPC. Subnet CIDRs are carved from this block when a tier does not specify explicit cidrs. Must be a valid IPv4 CIDR (e.g. 10.0.0.0/16)."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "secondary_cidrs" {
  type        = list(string)
  description = "Additional IPv4 CIDR blocks to associate with the VPC. Required when spoke VPC traffic needs NAT translation through the hub (centralized egress pattern). Each CIDR must be valid, non-overlapping, and should cover spoke VPC ranges."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.secondary_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All secondary CIDRs must be valid IPv4 CIDR blocks."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of every resource (e.g. \"network-hub\" yields \"network-hub-vpc\")."
  default     = "network-hub"

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}

variable "create_internet_gateway" {
  type        = bool
  description = "Whether to create and attach an internet gateway. Set to false for VPCs that need no direct internet egress (e.g. spoke VPCs reached only via the Transit Gateway)."
  default     = true
}

variable "tiers" {
  type = map(object({
    enabled                 = bool
    cidrs                   = optional(list(string))
    newbits                 = optional(number)
    netnum_base             = optional(number)
    map_public_ip_on_launch = optional(bool, false)
  }))
  description = <<-EOT
    Map of subnet tier name to its configuration. Enabled tiers create one
    subnet per Availability Zone. Per tier, CIDRs come from an explicit `cidrs`
    list (one per AZ) when set, otherwise they are derived from vpc_cidr via
    cidrsubnet(vpc_cidr, newbits, netnum_base + az_index). Provide either
    `cidrs` or both `newbits` and `netnum_base`. Set map_public_ip_on_launch
    true only for the public tier. The conventional tiers are `public`,
    `private`, `tgw`, and `resolver`; the `tgw` tier is reserved (dormant) for
    the future network-vpc-hub-attach project.
  EOT
}

variable "nat_availability_zones" {
  type        = list(string)
  description = "Availability Zones the regional NAT gateway is pinned to (manual mode, one EIP per AZ, lower standing cost). Empty (default) selects auto mode, where AWS manages AZ coverage and EIPs."
  default     = []
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
