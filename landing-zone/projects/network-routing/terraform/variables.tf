variable "region" {
  type        = string
  description = "AWS region of the network plane (must match the Control Tower home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of every resource (e.g. \"network\" yields \"network-spokes-rt\")."
  default     = "network"

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}

# ── Upstream IDs (from SSM via the pipeline) ─────────────────────────────────

variable "tgw_id" {
  type        = string
  description = "Transit Gateway ID, from network-tgw (/network.tgw.id)."

  validation {
    condition     = can(regex("^tgw-[a-z0-9]+$", var.tgw_id))
    error_message = "tgw_id must be a valid Transit Gateway ID (tgw-*)."
  }
}

variable "hub_vpc_id" {
  type        = string
  description = "Hub VPC ID, from network-vpc-hub (/network.vpc.id). Used to attach the hub VPC to the TGW and to locate the hub private route table."

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.hub_vpc_id))
    error_message = "hub_vpc_id must be a valid VPC ID (vpc-*)."
  }
}

variable "hub_vpc_cidr" {
  type        = string
  description = "Hub VPC IPv4 CIDR, from network-vpc-hub (/network.vpc.cidr). Advertised to on-prem via the TGW route table."

  validation {
    condition     = can(cidrhost(var.hub_vpc_cidr, 0))
    error_message = "hub_vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "hub_tgw_subnet_ids" {
  type        = list(string)
  description = "Hub VPC tgw-tier subnet IDs (one per AZ), from the network-vpc-hub blob (tgw_subnet_ids). The hub TGW VPC attachment places its ENIs in these subnets."
}

variable "vpn_attachment_ids" {
  type        = map(string)
  description = "Map of on-prem peer IP to TGW VPN attachment ID, from the network-s2s blob (vpn_attachment_ids). Empty map when network-s2s has not been applied yet."
  default     = {}
}

# ── Routing policy (declarative) ─────────────────────────────────────────────

variable "hub_route_table_ids" {
  type        = map(string)
  description = "Map of subnet tier name to route table ID for the hub VPC, from the network-vpc-hub blob (route_table_ids). Used to add the on-prem return route to the chosen tier's route table."
}

variable "regional_nat_gateway_id" {
  type        = string
  description = "Regional NAT gateway ID, from network-vpc-hub (/network.nat.regional_id). Target of the spoke-egress default route on the tgw-tier route table. Optional: leave empty to skip spoke egress (e.g. VPN-only topologies)."
  default     = ""
}

variable "enable_spoke_egress" {
  type        = bool
  description = <<-EOT
    When true, add a 0.0.0.0/0 route on the spoke-egress tier's route table
    pointing at the regional NAT gateway, so spoke VPCs reaching the hub over the
    TGW egress to the internet through the hub's NAT. Requires
    regional_nat_gateway_id and the spoke_egress_tier present in route_table_ids.
    Default false (opt-in).
  EOT
  default     = false
}

variable "spoke_egress_tier" {
  type        = string
  description = <<-EOT
    Hub VPC subnet tier whose route table receives the spoke-egress default route
    (0.0.0.0/0 -> regional NAT). Defaults to "tgw" — the tier hosting the TGW
    attachment ENIs, which is where spoke traffic lands when it enters the hub
    over the Transit Gateway. Override only if the attachment subnets use a
    different tier name. Must be present in route_table_ids when
    enable_spoke_egress is true.
  EOT
  default     = "tgw"
}

variable "onprem_cidrs" {
  type        = list(string)
  description = <<-EOT
    On-premises IPv4 CIDR blocks reachable through the Site-to-Site VPN. Each is
    added to the TGW route table as a static route pointing at the VPN
    attachment, and to the hub VPC route tables (see onprem_return_route_tiers)
    pointing at the TGW. These are customer values and live only in the consumer
    config.
  EOT
  default     = []

  validation {
    condition     = alltrue([for c in var.onprem_cidrs : can(cidrhost(c, 0))])
    error_message = "Every onprem_cidrs entry must be a valid IPv4 CIDR block."
  }
}

variable "onprem_return_route_tiers" {
  type        = list(string)
  description = <<-EOT
    Hub VPC subnet tiers whose route tables get the on-prem return route
    (onprem_cidr -> TGW). Defaults to ["private"], where workloads (and the SSM
    test instance) live. Set to the tiers actually enabled in network-vpc-hub:
    every listed tier must be present in route_table_ids, otherwise the apply
    fails with a clear error. The public tier hosts internet-facing ingress
    (ALB/NLB) and usually does not need to reach on-prem; add it only if a
    resource there must initiate traffic to on-prem.
  EOT
  default     = ["private"]
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
