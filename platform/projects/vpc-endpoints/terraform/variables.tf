# ── Region ────────────────────────────────────────────────────────────────────

variable "region" {
  type        = string
  description = "AWS region the endpoints are created in (must match the vpc project region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Pipeline inputs (from vpc / vpc-routes outputs) ───────────────────────────

variable "vpc_id" {
  type        = string
  description = "ID of the VPC. Sourced from the vpc project output."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "subnet_ids_by_tier" {
  type        = map(list(string))
  description = "Map of tier name to ordered subnet ID list, from vpc.subnet_ids_by_tier. Required only by endpoints[*] entries that set subnet_tier (Interface endpoints). Defaults to {} so a Gateway-only configuration does not need to wire this input."
  default     = {}
}

variable "route_table_ids" {
  type        = map(string)
  description = "Map of tier name to route table ID, from vpc-routes.route_table_ids. Required only by endpoints[*] entries that set route_table_tiers (Gateway endpoints). Defaults to {} so an Interface-only configuration — or a VPC with no route table project at all (e.g. a fully isolated VPC with no Transit Gateway) — does not need to wire this input."
  default     = {}
}

# ── Shared security group fallback ────────────────────────────────────────────
#
# Created only when at least one Interface endpoint entry omits
# security_group_ids. Skipped entirely when every Interface entry brings its
# own — see security_groups.tf. Endpoint services listen on different ports
# depending on configuration (e.g. MSK/IAM on 9098, TLS on 9094 — not
# universally 443), so the shared group opens all ports/protocols rather than
# guessing a single port; scope access with security_group_cidrs /
# security_group_source_security_group_ids instead.

variable "security_group_name" {
  type        = string
  description = "Name for the shared fallback security group. Left null (default) so AWS assigns a unique name and this never collides with an existing group — set explicitly only if a fixed name is required downstream."
  default     = null
}

variable "security_group_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the shared fallback security group, all ports/protocols. Defaults to unrestricted (0.0.0.0/0). Narrow it (e.g. to the VPC CIDR) if that default is too broad for your environment. Ignored when the shared group isn't created (see above)."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.security_group_cidrs : can(cidrhost(c, 0))])
    error_message = "All entries in security_group_cidrs must be valid CIDR blocks (e.g. 10.16.0.0/24)."
  }
}

variable "security_group_source_security_group_ids" {
  type        = list(string)
  description = "Additional security group IDs allowed to reach the shared fallback security group, all ports/protocols, on top of security_group_cidrs. Ignored when the shared group isn't created."
  default     = []

  validation {
    condition     = alltrue([for sg in var.security_group_source_security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", sg))])
    error_message = "All entries in security_group_source_security_group_ids must be valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}

variable "security_group_ports" {
  type        = list(number)
  description = "TCP/UDP ports to restrict the shared fallback security group's ingress to. Default is empty, which opens all ports/protocols (see security_groups.tf for why: not every endpoint service answers on 443, e.g. Amazon MSK varies by auth mode). Set this only when you know exactly which ports every endpoint sharing the group actually needs — e.g. [443] for an all-HTTPS set of endpoints, or [443, 9098] to add MSK/IAM alongside HTTPS ones."
  default     = []

  validation {
    condition     = alltrue([for p in var.security_group_ports : p >= 1 && p <= 65535])
    error_message = "Every entry in security_group_ports must be a valid TCP/UDP port (1-65535)."
  }
}

variable "security_group_protocol" {
  type        = string
  description = "IP protocol applied to every port in security_group_ports. Ignored when security_group_ports is empty (all protocols are already implied in that case)."
  default     = "tcp"

  validation {
    condition     = contains(["tcp", "udp"], var.security_group_protocol)
    error_message = "security_group_protocol must be 'tcp' or 'udp'."
  }
}

# ── Endpoints ─────────────────────────────────────────────────────────────────

variable "endpoints" {
  type = map(object({
    name                = optional(string)
    type                = string
    service             = optional(string)
    service_name        = optional(string)
    subnet_tier         = optional(string)
    route_table_tiers   = optional(list(string), [])
    security_group_ids  = optional(list(string), [])
    private_dns_enabled = optional(bool, true)
    policy_json         = optional(string)
  }))
  description = "Map of endpoint key to its configuration, resolved against subnet_ids_by_tier and route_table_ids by tier name instead of raw subnet/route-table IDs. See the project README for the field reference and examples."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.endpoints : contains(["Gateway", "Interface"], v.type)])
    error_message = "Each endpoint entry's 'type' must be 'Gateway' or 'Interface'."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : v.type != "Interface" || v.subnet_tier != null])
    error_message = "Every 'Interface' endpoint entry must set subnet_tier."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : v.type != "Interface" || contains(keys(var.subnet_ids_by_tier), v.subnet_tier)])
    error_message = "Every 'Interface' endpoint entry's subnet_tier must be a key present in subnet_ids_by_tier."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : v.type != "Gateway" || alltrue([for t in v.route_table_tiers : contains(keys(var.route_table_ids), t)])])
    error_message = "Every 'Gateway' endpoint entry's route_table_tiers must only reference keys present in route_table_ids."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : v.type != "Gateway" || v.subnet_tier == null])
    error_message = "'Gateway' endpoint entries must not set subnet_tier (an Interface-only field). Use route_table_tiers instead."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : v.type != "Interface" || length(v.route_table_tiers) == 0])
    error_message = "'Interface' endpoint entries must not set route_table_tiers (a Gateway-only field). Use subnet_tier and security_group_ids instead."
  }
}

# ── Policy ────────────────────────────────────────────────────────────────────

variable "organization_id" {
  type        = string
  description = "AWS Organizations ID, e.g. from @landing-zone/workload-parameters.organization_id (not currently published there — add it if this is wired). Passed straight through to the vpc-endpoints module; see its README for the org-scoped baseline policy it enables. Opt-in: leave null to keep the AWS default (unrestricted) policy."
  default     = null

  validation {
    condition     = var.organization_id == null || can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must be a valid AWS Organizations ID (e.g. o-xxxxxxxxxx) or null."
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
