variable "vpc_id" {
  type        = string
  description = "ID of the VPC the route tables are created in."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (vpc-...)."
  }
}

variable "route_tables" {
  type = map(object({
    name = string
  }))
  description = "Route tables to create, keyed by a caller-chosen key. `name` becomes the Name tag."
  default     = {}
}

variable "associations" {
  type = map(object({
    route_table_key = string
    subnet_id       = string
  }))
  description = "Subnet associations, keyed by a caller-chosen key. `route_table_key` must exist in route_tables."
  default     = {}

  validation {
    condition = alltrue([
      for k, a in var.associations : contains(keys(var.route_tables), a.route_table_key)
    ])
    error_message = "Every associations[*].route_table_key must be a key present in route_tables."
  }
}

variable "routes" {
  type = map(object({
    route_table_key        = string
    destination_cidr_block = string

    carrier_gateway_id        = optional(string)
    core_network_arn          = optional(string)
    egress_only_gateway_id    = optional(string)
    gateway_id                = optional(string)
    local_gateway_id          = optional(string)
    nat_gateway_id            = optional(string)
    network_interface_id      = optional(string)
    transit_gateway_id        = optional(string)
    vpc_endpoint_id           = optional(string)
    vpc_peering_connection_id = optional(string)
  }))
  description = <<-EOT
    Routes to create, keyed by a caller-chosen key. Each entry must set exactly
    one target argument. `gateway_id` is only for an internet or virtual private
    gateway — see the module README.
  EOT
  default     = {}

  validation {
    condition = alltrue([
      for k, r in var.routes : contains(keys(var.route_tables), r.route_table_key)
    ])
    error_message = "Every routes[*].route_table_key must be a key present in route_tables."
  }

  validation {
    condition = alltrue([
      for k, r in var.routes : can(cidrhost(r.destination_cidr_block, 0))
    ])
    error_message = "Every routes[*].destination_cidr_block must be a valid IPv4 CIDR block."
  }

  validation {
    condition = alltrue([
      for k, r in var.routes : length([
        for attr, v in r : v
        if !contains(["route_table_key", "destination_cidr_block"], attr) && v != null
      ]) == 1
    ])
    error_message = "Every routes[*] entry must set exactly one target argument."
  }

  validation {
    condition = length(distinct([
      for k, r in var.routes : "${r.route_table_key}|${r.destination_cidr_block}"
    ])) == length(var.routes)
    error_message = "Two routes share a route table and destination; a route table holds one route per destination."
  }
}
