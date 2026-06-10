variable "region" {
  type        = string
  description = "AWS region (must match the workload-vpc region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix used for route table Name tags (must match the value used in workload-vpc)."
  default     = "test1-vpc"

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}

variable "vpc_id" {
  type        = string
  description = "ID of the workload VPC, from workload-vpc.vpc_id."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (vpc-...)."
  }
}

variable "tgw_id" {
  type        = string
  description = "ID of the RAM-shared landing-zone Transit Gateway, from @landing-zone/workload-parameters.tgw_id."

  validation {
    condition     = can(regex("^tgw-[0-9a-f]+$", var.tgw_id))
    error_message = "tgw_id must be a valid Transit Gateway ID (tgw-...)."
  }
}

variable "tgw_attachment_id" {
  type        = string
  description = "ID of the TGW VPC attachment, from workload-vpc.tgw_attachment_id. Must be in available state (accepted by network-spokes) before this project can apply successfully."

  validation {
    condition     = can(regex("^tgw-attach-[0-9a-f]+$", var.tgw_attachment_id))
    error_message = "tgw_attachment_id must be a valid TGW attachment ID (tgw-attach-...)."
  }
}

variable "subnet_ids_by_tier" {
  type        = map(list(string))
  description = "Map of tier name to ordered subnet ID list, from workload-vpc.subnet_ids_by_tier. Used to look up which subnets belong to each egress tier."
}

variable "egress_tiers" {
  type        = list(string)
  description = "Tier names whose route table receives the 0.0.0.0/0 -> TGW route. Must match the tier names used in workload-vpc."
  default     = ["app", "data"]
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
