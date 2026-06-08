variable "vpc_id" {
  type        = string
  description = "ID of the hub VPC the regional NAT gateway is bound to. The VPC must have an attached internet gateway before the public regional NAT is created (enforce ordering at the call site with depends_on)."

  validation {
    condition     = length(var.vpc_id) > 0
    error_message = "vpc_id must not be empty."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = <<-EOT
    Availability Zones the regional NAT gateway operates in.

    When empty (default), the NAT gateway runs in auto mode: AWS expands it to
    every AZ that has workloads and manages EIP allocation automatically.

    When set, the NAT gateway runs in manual mode pinned to exactly these AZs,
    and the module allocates one Elastic IP per listed AZ. Pinning to fewer AZs
    lowers standing cost, at the expense of cross-AZ data-transfer charges for
    workloads in AZs not listed here (their egress is routed to a listed AZ).
  EOT
  default     = []
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of the regional NAT gateway and its EIPs (e.g. \"network-hub\" yields \"network-hub-nat\")."

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}
