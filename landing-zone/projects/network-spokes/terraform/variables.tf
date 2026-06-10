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
  description = "Prefix applied to the Name tag of each segment route table (e.g. \"network\" yields \"network-seg-<segment>\")."
  default     = "network"

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}

# ── Upstream IDs (from SSM via the pipeline) ─────────────────────────────────

variable "tgw_id" {
  type        = string
  description = "Transit Gateway ID, from network-tgw (/network.tgw.id). The TGW whose route tables (segments) this project creates and into which spoke attachments are accepted."

  validation {
    condition     = can(regex("^tgw-[a-z0-9]+$", var.tgw_id))
    error_message = "tgw_id must be a valid Transit Gateway ID (tgw-*)."
  }
}

# ── Shared-destination attachment IDs (read, not owned) ──────────────────────

variable "hub_attachment_id" {
  type        = string
  description = "Hub VPC TGW attachment ID, from network-routing (hub_attachment_id). Target of the per-segment hub route when a spoke declares 'hub' reachability. Leave empty when no spoke needs the hub."
  default     = ""

  validation {
    condition     = var.hub_attachment_id == "" || can(regex("^tgw-attach-[0-9a-f]+$", var.hub_attachment_id))
    error_message = "hub_attachment_id must be empty or a valid TGW attachment ID (tgw-attach-*)."
  }
}

variable "hub_vpc_cidr" {
  type        = string
  description = "Hub VPC IPv4 CIDR, from network-vpc-hub (/network.vpc.cidr). Destination of the per-segment hub route. Leave empty when no spoke needs the hub."
  default     = ""

  validation {
    condition     = var.hub_vpc_cidr == "" || can(cidrhost(var.hub_vpc_cidr, 0))
    error_message = "hub_vpc_cidr must be empty or a valid IPv4 CIDR block."
  }
}

variable "hub_tgw_route_table_id" {
  type        = string
  description = "TGW route table ID of the 'main' table owned by network-routing (tgw_route_table_id output). Used to write spoke-CIDR -> spoke-attachment return routes so the hub can initiate or return traffic to accepted spokes. Leave empty when no spoke needs hub reachability."
  default     = ""

  validation {
    condition     = var.hub_tgw_route_table_id == "" || can(regex("^tgw-rtb-[0-9a-f]+$", var.hub_tgw_route_table_id))
    error_message = "hub_tgw_route_table_id must be empty or a valid TGW route table ID (tgw-rtb-*)."
  }
}

variable "hub_vpc_route_table_ids" {
  type        = map(string)
  description = <<-EOT
    Map of hub VPC subnet tier name to route table ID, from network-vpc-hub (route_table_ids).
    network-spokes extracts the 'tgw' tier to write spoke-CIDR -> TGW routes so the hub NAT
    can return packets to spoke VPCs. Leave empty when no spoke declares 'hub' reachability.
  EOT
  default     = {}
}

variable "hub_nat_route_table_id" {
  type        = string
  description = <<-EOT
    ID of the route table automatically created by the regional NAT gateway, from
    network-vpc-hub (regional_nat_route_table_id). network-spokes writes spoke-CIDR -> TGW
    return routes into this table so the NAT can route reply packets back to spoke VPCs.
    Leave empty when no spoke declares 'hub' reachability.
  EOT
  default     = ""

  validation {
    condition     = var.hub_nat_route_table_id == "" || can(regex("^rtb-[0-9a-f]+$", var.hub_nat_route_table_id))
    error_message = "hub_nat_route_table_id must be empty or a valid route table ID (rtb-*)."
  }
}

variable "vpn_attachment_ids" {
  type        = map(string)
  description = "Map of on-prem peer IP to TGW VPN attachment ID, from the network-s2s blob (vpn_attachment_ids). Target of the per-segment on-prem routes when a spoke declares 'onprem' reachability. Empty map when network-s2s is absent."
  default     = {}
}

variable "onprem_cidrs" {
  type        = list(string)
  description = "On-premises IPv4 CIDR blocks reachable via the Site-to-Site VPN, from network-routing (onprem_cidrs). Destinations of the per-segment on-prem routes. Empty list when network-s2s is absent."
  default     = []

  validation {
    condition     = alltrue([for c in var.onprem_cidrs : can(cidrhost(c, 0))])
    error_message = "Every onprem_cidrs entry must be a valid IPv4 CIDR block."
  }
}

# ── Segmentation policy (declarative, governance-defined) ────────────────────

variable "segments" {
  type        = list(string)
  description = <<-EOT
    Names of the TGW route tables (segments) to create. Segment names are entirely
    governance-defined and express the customer's "who talks to whom" policy; no
    name is reserved. Isolation-by-default is structural: a spoke with empty
    allowed_destinations receives zero reachability routes regardless of its
    segment. An empty list creates zero segment route tables (scale-to-zero). The
    count must stay within the TGW route-table quota (default 20, adjustable).
  EOT
  default     = []
}

variable "spokes" {
  type = map(object({
    attachment_id        = string
    cidrs                = list(string)
    segment              = string
    allowed_destinations = list(string)
  }))
  description = <<-EOT
    Governance registry: a map keyed by a governance-chosen friendly name. Each
    entry is an object with:
      - attachment_id        the workload-account TGW VPC attachment to accept (tgw-attach-*)
      - cidrs                the spoke VPC CIDR(s)
      - segment              the segment (declared in var.segments) to associate the spoke with
      - allowed_destinations reserved keywords ("hub", "onprem") and/or friendly names of other
                             registry entries the spoke may reach; empty means the spoke reaches nothing
    Carries customer attachment IDs and CIDR plans, so it lives only in the
    private consumer repo. Empty (default) accepts no spokes.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for s in values(var.spokes) : can(regex("^tgw-attach-[0-9a-f]+$", s.attachment_id))])
    error_message = "Every spokes[*].attachment_id must be a valid TGW attachment ID (tgw-attach-*)."
  }

  validation {
    condition     = alltrue(flatten([for s in values(var.spokes) : [for c in s.cidrs : can(cidrhost(c, 0))]]))
    error_message = "Every spokes[*].cidrs entry must be a valid IPv4 CIDR block."
  }
}

# ── Tags (mandatory plumbing) ────────────────────────────────────────────────

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
