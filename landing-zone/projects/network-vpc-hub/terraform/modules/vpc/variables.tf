variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block for the hub VPC. Must be a syntactically valid IPv4 CIDR (e.g. 10.0.0.0/16)."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "secondary_cidrs" {
  type        = list(string)
  description = "Additional IPv4 CIDR blocks to associate with the VPC. Used to extend the VPC address space when source IPs from spoke VPCs need NAT translation. Each CIDR must be valid and non-overlapping."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.secondary_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All secondary CIDRs must be valid IPv4 CIDR blocks."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of every resource in this module (e.g. \"network-hub\" yields \"network-hub-vpc\")."

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}

variable "create_internet_gateway" {
  type        = bool
  description = "Whether to create and attach an internet gateway. Set to false for VPCs that do not need direct internet egress (e.g. spoke VPCs reached only via the Transit Gateway)."
  default     = true
}

variable "region" {
  type        = string
  description = <<-EOT
    AWS region the VPC is created in. Used to build the DHCP options domain_name:
    "ec2.internal" for us-east-1 and "<region>.compute.internal" otherwise, per
    the EC2 internal-DNS convention.
  EOT

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region code (e.g. eu-central-2)."
  }
}
