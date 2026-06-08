variable "region" {
  type        = string
  description = "AWS region where the Site-to-Site VPN resources are created."

  validation {
    condition     = length(var.region) > 0
    error_message = "region must not be empty."
  }
}

variable "tgw_id" {
  type        = string
  description = "ID of the Transit Gateway to which the VPN connection(s) are attached."

  validation {
    condition     = can(regex("^tgw-[a-z0-9]+$", var.tgw_id))
    error_message = "tgw_id must be a valid Transit Gateway ID (tgw-*)."
  }
}

variable "customer_gateway_ips" {
  type        = list(string)
  description = <<-EOT
    List of on-premises customer gateway public IP addresses. Single IP creates
    one VPN connection with 2 tunnels. Two IPs create two VPN connections with
    4 tunnels total (high availability topology).
  EOT

  validation {
    condition     = length(var.customer_gateway_ips) > 0 && length(var.customer_gateway_ips) <= 2
    error_message = "customer_gateway_ips must contain 1 or 2 IP addresses."
  }

  validation {
    condition     = alltrue([for ip in var.customer_gateway_ips : can(cidrhost("${ip}/32", 0))])
    error_message = "All customer_gateway_ips must be valid IPv4 addresses."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the Name tag of every resource (e.g. \"network-s2s\" yields \"network-s2s-cgw-0\")."

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}

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
