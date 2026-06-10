variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block for the workload VPC. Must be a syntactically valid IPv4 CIDR (e.g. 10.16.0.0/16)."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.16.0.0/16)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of every resource in this module (e.g. \"test1-vpc\" yields \"test1-vpc-vpc\")."

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
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
