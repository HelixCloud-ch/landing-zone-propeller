# ── Network ───────────────────────────────────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID to create endpoints in."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

# ── Endpoints ─────────────────────────────────────────────────────────────────

variable "endpoints" {
  type = map(object({
    name                = optional(string)
    type                = string
    service             = optional(string)
    service_name        = optional(string)
    subnet_ids          = optional(list(string), [])
    route_table_ids     = optional(list(string), [])
    security_group_ids  = optional(list(string), [])
    private_dns_enabled = optional(bool, true)
    policy_json         = optional(string)
  }))
  description = "Map of endpoint key to its configuration. The key doubles as the AWS service short name and the resource's Name tag unless overridden. See the module README for the field reference and examples."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.endpoints : contains(["Gateway", "Interface"], v.type)])
    error_message = "Each endpoint entry's 'type' must be 'Gateway' or 'Interface'."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : !(v.service != null && v.service_name != null)])
    error_message = "Each endpoint entry must set at most one of 'service' or 'service_name', not both."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : v.type != "Interface" || length(v.subnet_ids) > 0])
    error_message = "Every 'Interface' endpoint entry must set a non-empty subnet_ids."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : v.type != "Interface" || length(v.route_table_ids) == 0])
    error_message = "'Interface' endpoint entries must not set route_table_ids (a Gateway-only field). Use subnet_ids and security_group_ids instead."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : v.type != "Gateway" || (length(v.subnet_ids) == 0 && length(v.security_group_ids) == 0)])
    error_message = "'Gateway' endpoint entries must not set subnet_ids or security_group_ids (Interface-only fields). Use route_table_ids instead."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : alltrue([for s in v.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])])
    error_message = "Every entry in an endpoint's subnet_ids must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : alltrue([for rt in v.route_table_ids : can(regex("^rtb-[0-9a-f]{8,17}$", rt))])])
    error_message = "Every entry in an endpoint's route_table_ids must be a valid route table ID (e.g. rtb-0123456789abcdef0)."
  }

  validation {
    condition     = alltrue([for k, v in var.endpoints : alltrue([for sg in v.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", sg))])])
    error_message = "Every entry in an endpoint's security_group_ids must be a valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}

# ── Policy ────────────────────────────────────────────────────────────────────

variable "organization_id" {
  type        = string
  description = "AWS Organizations ID (e.g. \"o-xxxxxxxxxx\"). When set, every endpoint whose service supports endpoint policies gets a baseline policy denying access to principals outside this organization, unless the endpoint sets its own policy_json. Opt-in: leave null to keep the AWS default (unrestricted) policy."
  default     = null

  validation {
    condition     = var.organization_id == null || can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must be a valid AWS Organizations ID (e.g. o-xxxxxxxxxx) or null."
  }
}
