variable "region" {
  type        = string
  description = "AWS region."
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Targets ───────────────────────────────────────────────────────────────────
variable "transit_gateway_id" {
  type        = string
  description = "Default transit gateway for connections that set no target. See README for targets."
  default     = null
  validation {
    condition     = var.transit_gateway_id == null ? true : can(regex("^tgw-[0-9a-f]+$", var.transit_gateway_id))
    error_message = "transit_gateway_id must look like tgw-0123456789abcdef0."
  }
}

variable "vpn_gateways" {
  type = map(object({
    name            = optional(string)
    vpc_id          = optional(string)
    vpn_gateway_id  = optional(string)
    amazon_side_asn = optional(number)
    route_table_ids = optional(list(string), [])
  }))
  description = <<-EOT
    Virtual private gateways, keyed by a stable id (the state address).
    Each item creates a gateway (vpc_id) or uses an existing one (vpn_gateway_id).
    A connection uses an item with vpn_gateway_key. See README for all fields.
  EOT
  default     = {}
  validation {
    condition     = alltrue([for k, _ in var.vpn_gateways : can(regex("^[a-z0-9-]{1,32}$", k))])
    error_message = "Virtual private gateway keys must match ^[a-z0-9-]{1,32}$."
  }
  validation {
    condition     = alltrue([for g in values(var.vpn_gateways) : (g.vpc_id != null) != (g.vpn_gateway_id != null)])
    error_message = "Each virtual private gateway must set exactly one of vpc_id and vpn_gateway_id."
  }
  validation {
    condition = alltrue([
      for g in values(var.vpn_gateways) :
      (g.vpc_id == null ? true : can(regex("^vpc-[0-9a-f]+$", g.vpc_id))) &&
      (g.vpn_gateway_id == null ? true : can(regex("^vgw-[0-9a-f]+$", g.vpn_gateway_id))) &&
      alltrue([for id in g.route_table_ids : can(regex("^rtb-[0-9a-f]+$", id))])
    ])
    error_message = "vpc_id, vpn_gateway_id and route_table_ids must look like vpc-..., vgw-... and rtb-...."
  }
  validation {
    condition = alltrue([
      for g in values(var.vpn_gateways) :
      g.amazon_side_asn == null ? true : (
        g.vpc_id != null && (
          (g.amazon_side_asn >= 64512 && g.amazon_side_asn <= 65534) ||
          (g.amazon_side_asn >= 4200000000 && g.amazon_side_asn <= 4294967294)
        )
      )
    ])
    error_message = "amazon_side_asn needs vpc_id and must be in 64512-65534 or 4200000000-4294967294."
  }
  validation {
    condition = alltrue([
      for g in values(var.vpn_gateways) :
      g.name == null ? true : (length(g.name) >= 1 && length(g.name) <= 128)
    ])
    error_message = "name must be 1 to 128 characters long."
  }
  validation {
    condition     = length(distinct([for k, g in var.vpn_gateways : coalesce(g.name, k)])) == length(var.vpn_gateways)
    error_message = "Virtual private gateway names must be unique."
  }
  validation {
    condition = (
      length(distinct([for g in values(var.vpn_gateways) : g.vpc_id if g.vpc_id != null])) == length([for g in values(var.vpn_gateways) : g.vpc_id if g.vpc_id != null]) &&
      length(distinct([for g in values(var.vpn_gateways) : g.vpn_gateway_id if g.vpn_gateway_id != null])) == length([for g in values(var.vpn_gateways) : g.vpn_gateway_id if g.vpn_gateway_id != null])
    )
    error_message = "A vpc_id or a vpn_gateway_id can appear in only one item (a VPC has one gateway)."
  }
}

# ── Customer gateways ─────────────────────────────────────────────────────────
variable "customer_gateways" {
  type = map(object({
    name            = optional(string)
    ip_address      = optional(string)
    bgp_asn         = optional(number, 65000)
    certificate_arn = optional(string)
    device_name     = optional(string)
  }))
  description = <<-EOT
    Customer gateways to create, keyed by a stable id (the state address).
    Each needs ip_address or certificate_arn. Changing ip_address or bgp_asn
    replaces the gateway and its connections.
  EOT
  default     = {}
  validation {
    condition     = alltrue([for k, _ in var.customer_gateways : can(regex("^[a-z0-9-]{1,32}$", k))])
    error_message = "Customer gateway keys must match ^[a-z0-9-]{1,32}$."
  }
  validation {
    condition = alltrue([
      for c in values(var.customer_gateways) :
      c.name == null ? true : (length(c.name) >= 1 && length(c.name) <= 128)
    ])
    error_message = "name must be 1 to 128 characters long."
  }
  validation {
    condition     = length(distinct([for k, c in var.customer_gateways : coalesce(c.name, k)])) == length(var.customer_gateways)
    error_message = "Customer gateway names must be unique."
  }
  validation {
    condition     = alltrue([for c in values(var.customer_gateways) : c.ip_address != null || c.certificate_arn != null])
    error_message = "Each customer gateway needs ip_address or certificate_arn."
  }
  validation {
    condition = alltrue([
      for c in values(var.customer_gateways) :
      c.ip_address == null ? true : (can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", c.ip_address)) && can(cidrhost("${c.ip_address}/32", 0)))
    ])
    error_message = "ip_address must be a valid IPv4 address."
  }
  validation {
    condition     = alltrue([for c in values(var.customer_gateways) : floor(c.bgp_asn) == c.bgp_asn && c.bgp_asn >= 1 && c.bgp_asn <= 4294967295])
    error_message = "bgp_asn must be an integer from 1 to 4294967295."
  }
  validation {
    condition = alltrue([
      for c in values(var.customer_gateways) :
      c.certificate_arn == null ? true : can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/.+$", c.certificate_arn))
    ])
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

# ── Connections ───────────────────────────────────────────────────────────────
variable "connections" {
  type = map(object({
    name                     = optional(string)
    customer_gateway_key     = optional(string)
    customer_gateway_id      = optional(string)
    transit_gateway_id       = optional(string)
    vpn_gateway_key          = optional(string)
    unattached               = optional(bool, false)
    routing                  = optional(string, "bgp")
    static_routes            = optional(list(string), [])
    tunnel_bandwidth         = optional(string)
    enable_acceleration      = optional(bool)
    local_ipv4_network_cidr  = optional(string)
    remote_ipv4_network_cidr = optional(string)
    preshared_key_storage    = optional(string, "Standard")
    log_group_arn            = optional(string)
    bgp_log_group_arn        = optional(string)
    tunnel_options = optional(object({
      ike_versions                    = optional(list(string))
      phase1_encryption_algorithms    = optional(list(string))
      phase2_encryption_algorithms    = optional(list(string))
      phase1_integrity_algorithms     = optional(list(string))
      phase2_integrity_algorithms     = optional(list(string))
      phase1_dh_group_numbers         = optional(list(number))
      phase2_dh_group_numbers         = optional(list(number))
      phase1_lifetime_seconds         = optional(number)
      phase2_lifetime_seconds         = optional(number)
      rekey_margin_time_seconds       = optional(number)
      rekey_fuzz_percentage           = optional(number)
      replay_window_size              = optional(number)
      dpd_timeout_seconds             = optional(number)
      dpd_timeout_action              = optional(string)
      startup_action                  = optional(string)
      enable_tunnel_lifecycle_control = optional(bool)
    }), {})
    tunnel1_inside_cidr = optional(string)
    tunnel2_inside_cidr = optional(string)
  }))
  description = <<-EOT
    VPN connections, keyed by a stable id (the state address). Each uses a
    customer gateway and one target: transit_gateway_id, vpn_gateway_key or
    none. Field rules are enforced by the shared module. See README.
  EOT
  default     = {}
  validation {
    condition     = alltrue([for k, _ in var.connections : can(regex("^[a-z0-9-]{1,32}$", k))])
    error_message = "Connection keys must match ^[a-z0-9-]{1,32}$."
  }
  validation {
    condition = alltrue([
      for c in values(var.connections) :
      c.name == null ? true : (length(c.name) >= 1 && length(c.name) <= 128)
    ])
    error_message = "name must be 1 to 128 characters long."
  }
  validation {
    condition     = length(distinct([for k, c in var.connections : coalesce(c.name, k)])) == length(var.connections)
    error_message = "Connection names must be unique."
  }
  validation {
    condition     = alltrue([for c in values(var.connections) : (c.customer_gateway_key == null) != (c.customer_gateway_id == null)])
    error_message = "Each connection must set exactly one of customer_gateway_key and customer_gateway_id."
  }
  validation {
    condition = alltrue([
      for c in values(var.connections) :
      c.customer_gateway_key == null ? true : contains(keys(var.customer_gateways), c.customer_gateway_key)
    ])
    error_message = "Every customer_gateway_key must exist in customer_gateways."
  }
  validation {
    condition = alltrue([
      for c in values(var.connections) :
      c.vpn_gateway_key == null ? true : contains(keys(var.vpn_gateways), c.vpn_gateway_key)
    ])
    error_message = "Every vpn_gateway_key must exist in vpn_gateways."
  }
  validation {
    condition = alltrue([
      for c in values(var.connections) :
      (c.transit_gateway_id != null ? 1 : 0) + (c.vpn_gateway_key != null ? 1 : 0) + (c.unattached ? 1 : 0) <= 1
    ])
    error_message = "A connection can set only one of transit_gateway_id, vpn_gateway_key and unattached."
  }
  validation {
    condition = alltrue([
      for c in values(var.connections) :
      c.transit_gateway_id == null ? true : can(regex("^tgw-[0-9a-f]+$", c.transit_gateway_id))
    ])
    error_message = "transit_gateway_id must look like tgw-0123456789abcdef0."
  }
  validation {
    condition = length(distinct([
      for k, c in var.connections :
      try(
        "${c.customer_gateway_key != null ? "key:${c.customer_gateway_key}" : "id:${c.customer_gateway_id}"}|${
          c.unattached ? "none" : (
            c.vpn_gateway_key != null ? "vgw:${c.vpn_gateway_key}" : (
              (c.transit_gateway_id != null || var.transit_gateway_id != null) ? "tgw:${k}" : "none"
            )
          )
        }",
        "invalid:${k}"
      )
    ])) == length(var.connections)
    error_message = "A customer gateway can serve several connections only on different targets, or on transit gateways."
  }
}

# ── Tags ──────────────────────────────────────────────────────────────────────
variable "tags" {
  type        = map(string)
  description = "Per-project tags."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Pipeline-wide tags."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Framework-managed tags."
  default     = {}
}
