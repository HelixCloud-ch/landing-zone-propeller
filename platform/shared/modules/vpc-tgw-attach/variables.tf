variable "vpc_id" {
  type        = string
  description = "ID of the workload VPC to attach to the Transit Gateway."

  validation {
    condition     = length(var.vpc_id) > 0
    error_message = "vpc_id must not be empty."
  }
}

variable "tgw_id" {
  type        = string
  description = "ID of the RAM-shared landing-zone Transit Gateway."

  validation {
    condition     = can(regex("^tgw-[0-9a-f]+$", var.tgw_id))
    error_message = "tgw_id must be a valid Transit Gateway ID (tgw-...)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs (one per AZ) used by the TGW VPC attachment for its ENIs. Should come from the dedicated tgw-attach tier."

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet (one per AZ used by the attachment)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of the attachment (e.g. \"test1-vpc\" yields \"test1-vpc-tgw-attach\")."

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}
