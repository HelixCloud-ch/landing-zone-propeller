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
  type        = string
  description = "JSON-encoded list of hub VPC tgw-tier subnet IDs (one per AZ), from the network-vpc-hub blob (tgw_subnet_ids). The hub TGW VPC attachment places its ENIs in these subnets."
}

variable "vpn_attachment_ids" {
  type        = string
  description = "JSON-encoded map of on-prem peer IP to TGW VPN attachment ID, from the network-s2s blob (vpn_attachment_ids). Pass an empty string or '{}' when network-s2s has not been applied yet."
  default     = "{}"
}

# ── Routing policy (declarative) ─────────────────────────────────────────────

variable "hub_route_table_ids" {
  type        = string
  description = "JSON-encoded map of subnet tier name to route table ID for the hub VPC, from the network-vpc-hub blob (route_table_ids). Used to add the on-prem return route to the private tier's route table."
}

variable "onprem_cidrs" {
  type        = list(string)
  description = <<-EOT
    On-premises IPv4 CIDR blocks reachable through the Site-to-Site VPN. Each is
    added to the TGW route table as a static route pointing at the VPN
    attachment, and to the hub VPC private route table pointing at the TGW.
    These are customer values and live only in the consumer config.
  EOT
  default     = []

  validation {
    condition     = alltrue([for c in var.onprem_cidrs : can(cidrhost(c, 0))])
    error_message = "Every onprem_cidrs entry must be a valid IPv4 CIDR block."
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
