variable "vpc_id" {
  type        = string
  description = "ID of the workload VPC the subnets are created in."

  validation {
    condition     = length(var.vpc_id) > 0
    error_message = "vpc_id must not be empty."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block of the workload VPC. Subnet CIDRs are carved from this block. Must be a valid IPv4 CIDR (e.g. 10.16.0.0/16)."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.16.0.0/16)."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Ordered list of Availability Zone names. Enabled tiers create one subnet per AZ in this list; the list index is the az_index used for deterministic CIDR carving."

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "availability_zones must contain at least one AZ name."
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
    Map of subnet tier name to its configuration. Enabled tiers produce one
    subnet per Availability Zone.

    CIDR selection per tier, in order of precedence:
      1. cidrs: explicit list of CIDR blocks, one per AZ (cidrs[az_index]).
         Use this to pin exact ranges.
      2. newbits + netnum_base: derive CIDRs automatically as
         cidrsubnet(vpc_cidr, newbits, netnum_base + az_index). netnum_base
         values must be spaced far enough apart per tier that ranges never
         overlap.

    Provide either cidrs or both newbits and netnum_base. map_public_ip_on_launch
    should be left at the default false for workload VPCs (no public tier).

    extra_tags: additional tags merged onto every subnet in this tier on top
    of the provider default_tags. Use this for controller-discovery tags such
    as kubernetes.io/role/internal-elb or kubernetes.io/role/elb. Tags set
    here take precedence over the provider default_tags for the same key.
  EOT

  validation {
    condition = alltrue([
      for t in var.tiers :
      t.cidrs != null || (t.newbits != null && t.netnum_base != null)
    ])
    error_message = "Each tier must provide either an explicit cidrs list or both newbits and netnum_base."
  }

  validation {
    condition = alltrue([
      for t in var.tiers :
      t.cidrs == null ? true : alltrue([for c in t.cidrs : can(cidrhost(c, 0))])
    ])
    error_message = "Every entry in a tier's cidrs list must be a valid IPv4 CIDR block."
  }

  validation {
    condition = alltrue([
      for t in var.tiers :
      t.cidrs == null ? true : length(t.cidrs) >= length(var.availability_zones)
    ])
    error_message = "A tier's cidrs list must contain at least one CIDR per Availability Zone (length >= length(availability_zones))."
  }

  validation {
    condition = alltrue([
      for t in var.tiers :
      t.newbits == null ? true : (t.newbits > 0 && t.netnum_base >= 0)
    ])
    error_message = "When using computed CIDRs, newbits must be > 0 and netnum_base must be >= 0."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of every subnet (e.g. \"test1-vpc\" yields \"test1-vpc-app-<az>\")."

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}
