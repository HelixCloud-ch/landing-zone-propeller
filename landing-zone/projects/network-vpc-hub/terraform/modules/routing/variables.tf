variable "vpc_id" {
  type        = string
  description = "ID of the hub VPC the route tables belong to."

  validation {
    condition     = length(var.vpc_id) > 0
    error_message = "vpc_id must not be empty."
  }
}

variable "subnets_by_tier" {
  type = map(list(object({
    id   = string
    az   = string
    cidr = string
  })))
  description = <<-EOT
    Map of subnet tier name to its ordered list of subnet objects ({ id, az,
    cidr }), as emitted by the subnets module. One route table is created per
    tier that has at least one subnet; every subnet in a tier is associated with
    that tier's table.
  EOT
}

variable "igw_id" {
  type        = string
  description = "ID of the internet gateway, used as the target of the public tier's 0.0.0.0/0 route. May be null when internet_gateway_enabled is false."
  default     = null
}

variable "internet_gateway_enabled" {
  type        = bool
  description = "Whether an internet gateway exists. Gates creation of the public tier's default route at plan time (the igw_id value itself is unknown until apply, so it cannot gate count/for_each)."
  default     = true
}

variable "regional_nat_gateway_id" {
  type        = string
  description = "ID of the regional NAT gateway, used as the target of the private tier's 0.0.0.0/0 route."
  default     = null
}

variable "public_tier" {
  type        = string
  description = "Name of the tier treated as public (its route table receives the 0.0.0.0/0 -> IGW route)."
  default     = "public"
}

variable "private_tier" {
  type        = string
  description = "Name of the tier treated as private (its route table receives the 0.0.0.0/0 -> regional NAT route)."
  default     = "private"
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of every route table (e.g. \"network-hub\" yields \"network-hub-private-rt\")."

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}
