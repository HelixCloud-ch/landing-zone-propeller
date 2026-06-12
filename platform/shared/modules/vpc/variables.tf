variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "private_subnets" {
  type        = list(string)
  description = "List of CIDR blocks for private subnets (one per AZ)."

  validation {
    condition     = length(var.private_subnets) >= 2
    error_message = "At least 2 private subnets are required."
  }
}

variable "public_subnets" {
  type        = list(string)
  description = "List of CIDR blocks for public subnets (one per AZ). Leave empty to skip public subnets."
  default     = []
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones to use. Must match the length of private_subnets."

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required."
  }
}

variable "name" {
  type        = string
  description = "Name prefix for all VPC resources."
}

variable "single_nat_gateway" {
  type        = bool
  description = "Use a single NAT gateway instead of one per AZ. Reduces cost at the expense of AZ redundancy."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Additional tags applied to all resources."
  default     = {}
}

variable "private_subnet_tags" {
  type        = map(string)
  description = "Additional tags applied to private subnets (e.g. Kubernetes LB discovery tags)."
  default     = {}
}

variable "public_subnet_tags" {
  type        = map(string)
  description = "Additional tags applied to public subnets (e.g. Kubernetes LB discovery tags)."
  default     = {}
}
