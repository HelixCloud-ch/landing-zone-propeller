variable "region" {
  type        = string
  description = "AWS region (must match the vpc project region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix used for route table Name tags (must match the value used in the vpc project)."
  default     = "test1-vpc"

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}

# ── Pipeline inputs ──────────────────────────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "ID of the VPC, from vpc.vpc_id."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (vpc-...)."
  }
}

variable "subnet_ids_by_tier" {
  type        = map(list(string))
  description = "Map of tier name to ordered subnet ID list, from vpc.subnet_ids_by_tier."
}

# ── Routing policy ───────────────────────────────────────────────────────────

variable "tier_routes" {
  type = map(list(object({
    destination = string
    igw         = optional(bool)
    vgw         = optional(bool)
    tgw_key     = optional(string)
    natgw_key   = optional(string)
    peering_key = optional(string)
    vpce_key    = optional(string)
    target_key  = optional(string)
  })))
  description = <<-EOT
    Per-tier routes. Each entry sets exactly one target field. `destination` is
    an IPv4 CIDR. See README for the target field semantics.
  EOT
  default     = {}

  validation {
    condition = alltrue(flatten([
      for tier, routes in var.tier_routes : [
        for r in routes : can(cidrhost(r.destination, 0))
      ]
    ]))
    error_message = "Every tier_routes[*].destination must be a valid IPv4 CIDR block (e.g. 0.0.0.0/0)."
  }

  validation {
    condition = alltrue(flatten([
      for tier, routes in var.tier_routes : [
        for r in routes : length([
          for field in [
            r.igw == true ? "igw" : null,
            r.vgw == true ? "vgw" : null,
            r.tgw_key,
            r.natgw_key,
            r.peering_key,
            r.vpce_key,
            r.target_key,
          ] : field if field != null
        ]) == 1
      ]
    ]))
    error_message = "Every tier_routes[*] entry must set exactly one target field (igw, vgw, tgw_key, natgw_key, peering_key, vpce_key, or target_key)."
  }

  validation {
    condition = alltrue([
      for tier, routes in var.tier_routes :
      length(distinct([for r in routes : r.destination])) == length(routes)
    ])
    error_message = "A tier declares the same destination twice; a route table can hold only one route per destination."
  }
}

# ── Target ID variables ──────────────────────────────────────────────────────

variable "igw_id" {
  type        = string
  description = "Internet Gateway ID, from vpc-igw.igw_id. Referenced by `igw = true`."
  default     = null

  validation {
    condition     = var.igw_id == null || can(regex("^igw-[0-9a-f]+$", var.igw_id))
    error_message = "igw_id must be a valid Internet Gateway ID (igw-...) or null."
  }
}

variable "vgw_id" {
  type        = string
  description = "Virtual Private Gateway ID. Referenced by `vgw = true`."
  default     = null

  validation {
    condition     = var.vgw_id == null || can(regex("^vgw-[0-9a-f]+$", var.vgw_id))
    error_message = "vgw_id must be a valid Virtual Private Gateway ID (vgw-...) or null."
  }
}

variable "tgw_ids" {
  type        = map(string)
  description = "Transit Gateway IDs by key. Referenced by `tgw_key`. AWS allows up to 5 TGW attachments per VPC."
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.tgw_ids : can(regex("^tgw-[0-9a-f]+$", v))
    ])
    error_message = "Every tgw_ids value must be a valid Transit Gateway ID (tgw-...)."
  }
}

variable "natgw_ids" {
  type        = map(string)
  description = "NAT Gateway IDs by key. Referenced by `natgw_key`."
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.natgw_ids : can(regex("^nat-[0-9a-f]+$", v))
    ])
    error_message = "Every natgw_ids value must be a valid NAT Gateway ID (nat-...)."
  }
}

variable "peering_ids" {
  type        = map(string)
  description = "VPC peering connection IDs by key. Referenced by `peering_key`."
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.peering_ids : can(regex("^pcx-[0-9a-f]+$", v))
    ])
    error_message = "Every peering_ids value must be a valid VPC peering ID (pcx-...)."
  }
}

variable "vpc_endpoint_ids" {
  type        = map(string)
  description = <<-EOT
    VPC endpoint IDs by key, for Gateway Load Balancer endpoints used as a
    route target. Referenced by `vpce_key`. Gateway endpoints (S3, DynamoDB)
    do not belong here.
  EOT
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.vpc_endpoint_ids : can(regex("^vpce-[0-9a-f]+$", v))
    ])
    error_message = "Every vpc_endpoint_ids value must be a valid VPC endpoint ID (vpce-...)."
  }
}

variable "route_targets" {
  type        = map(string)
  description = <<-EOT
    Extra targets by key, for types with no dedicated variable (ENI, carrier
    gateway, Outpost local gateway, Cloud WAN core network ARN). Referenced by
    `target_key`. The aws_route argument is derived from the ID prefix.
  EOT
  default     = {}
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
