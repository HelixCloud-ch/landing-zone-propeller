variable "name" {
  type        = string
  description = "Value of the Name tag of the VPN connection."
  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 128
    error_message = "name must be 1 to 128 characters long."
  }
}

variable "customer_gateway_id" {
  type        = string
  description = "ID of an existing customer gateway."
  validation {
    condition     = can(regex("^cgw-[0-9a-f]+$", var.customer_gateway_id))
    error_message = "customer_gateway_id must look like cgw-0123456789abcdef0."
  }
}

variable "target_type" {
  type        = string
  description = "Target gateway type: none (unassociated), tgw or vgw."
  default     = "none"
  validation {
    condition     = contains(["none", "tgw", "vgw"], var.target_type)
    error_message = "target_type must be one of none, tgw or vgw."
  }
}

variable "target_gateway_id" {
  type        = string
  description = "ID of the transit gateway or virtual private gateway. Null only when target_type is none."
  default     = null
  validation {
    condition     = (var.target_type == "none") == (var.target_gateway_id == null)
    error_message = "target_gateway_id must be null when target_type is none, and set otherwise."
  }
}

variable "routing" {
  type        = string
  description = "Routing mode: bgp (dynamic) or static."
  default     = "bgp"
  validation {
    condition     = contains(["bgp", "static"], var.routing)
    error_message = "routing must be bgp or static."
  }
}

variable "static_routes" {
  type        = list(string)
  description = "Static route CIDRs of the on-premises network. Only with target_type vgw and routing static."
  default     = []
  validation {
    condition = alltrue([
      for r in var.static_routes :
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", r)) && can(cidrhost(r, 0))
    ])
    error_message = "Every static route must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = length(var.static_routes) == 0 || (var.target_type == "vgw" && var.routing == "static")
    error_message = "static_routes can be set only when target_type is vgw and routing is static."
  }
}

variable "tunnel_bandwidth" {
  type        = string
  description = "standard or large. Null uses the AWS default. Large needs a transit gateway."
  default     = null
  validation {
    condition     = var.tunnel_bandwidth == null ? true : contains(["standard", "large"], var.tunnel_bandwidth)
    error_message = "tunnel_bandwidth must be null, standard or large."
  }
  validation {
    condition     = var.tunnel_bandwidth != "large" || (var.target_type == "tgw" && var.enable_acceleration != true)
    error_message = "tunnel_bandwidth large needs a transit gateway target and no acceleration."
  }
}

variable "enable_acceleration" {
  type        = bool
  description = "Enable accelerated VPN. Null uses the AWS default. Only with target_type tgw."
  default     = null
  validation {
    condition     = var.enable_acceleration != true || var.target_type == "tgw"
    error_message = "enable_acceleration is supported only when target_type is tgw."
  }
}

variable "local_ipv4_network_cidr" {
  type        = string
  description = "IPv4 CIDR on the customer gateway side. Null uses the AWS default."
  default     = null
  validation {
    condition     = var.local_ipv4_network_cidr == null ? true : (can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", var.local_ipv4_network_cidr)) && can(cidrhost(var.local_ipv4_network_cidr, 0)))
    error_message = "local_ipv4_network_cidr must be a valid IPv4 CIDR block."
  }
}

variable "remote_ipv4_network_cidr" {
  type        = string
  description = "IPv4 CIDR on the AWS side. Null uses the AWS default."
  default     = null
  validation {
    condition     = var.remote_ipv4_network_cidr == null ? true : (can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", var.remote_ipv4_network_cidr)) && can(cidrhost(var.remote_ipv4_network_cidr, 0)))
    error_message = "remote_ipv4_network_cidr must be a valid IPv4 CIDR block."
  }
}

variable "preshared_key_storage" {
  type        = string
  description = "Where AWS keeps the pre-shared keys: Standard (VPN service) or SecretsManager."
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "SecretsManager"], var.preshared_key_storage)
    error_message = "preshared_key_storage must be Standard or SecretsManager."
  }
}

variable "log_group_arn" {
  type        = string
  description = "ARN of a CloudWatch log group for the logs of both tunnels. Null disables tunnel logs."
  default     = null
  validation {
    condition     = var.log_group_arn == null ? true : can(regex("^arn:aws[a-z-]*:logs:", var.log_group_arn))
    error_message = "log_group_arn must be a CloudWatch Logs ARN."
  }
}

variable "bgp_log_group_arn" {
  type        = string
  description = "ARN of a CloudWatch log group for the BGP logs of both tunnels. Null disables BGP logs."
  default     = null
  validation {
    condition     = var.bgp_log_group_arn == null ? true : can(regex("^arn:aws[a-z-]*:logs:", var.bgp_log_group_arn))
    error_message = "bgp_log_group_arn must be a CloudWatch Logs ARN."
  }
}

variable "tunnel_options" {
  type = object({
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
  })
  description = <<-EOT
    Options applied to both tunnels. Every field is optional; null keeps
    the AWS default. Changing an option restarts the tunnel.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for v in(var.tunnel_options.ike_versions == null ? [] : var.tunnel_options.ike_versions) : contains(["ikev1", "ikev2"], v)])
    error_message = "ike_versions can contain only ikev1 and ikev2."
  }
  validation {
    condition = alltrue([
      for v in concat(
        var.tunnel_options.phase1_encryption_algorithms == null ? [] : var.tunnel_options.phase1_encryption_algorithms,
        var.tunnel_options.phase2_encryption_algorithms == null ? [] : var.tunnel_options.phase2_encryption_algorithms
      ) : contains(["AES128", "AES256", "AES128-GCM-16", "AES256-GCM-16"], v)
    ])
    error_message = "Encryption algorithms can be AES128, AES256, AES128-GCM-16 or AES256-GCM-16."
  }
  validation {
    condition = alltrue([
      for v in concat(
        var.tunnel_options.phase1_integrity_algorithms == null ? [] : var.tunnel_options.phase1_integrity_algorithms,
        var.tunnel_options.phase2_integrity_algorithms == null ? [] : var.tunnel_options.phase2_integrity_algorithms
      ) : contains(["SHA1", "SHA2-256", "SHA2-384", "SHA2-512"], v)
    ])
    error_message = "Integrity algorithms can be SHA1, SHA2-256, SHA2-384 or SHA2-512."
  }
  validation {
    condition     = alltrue([for v in(var.tunnel_options.phase1_dh_group_numbers == null ? [] : var.tunnel_options.phase1_dh_group_numbers) : contains([2, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24], v)])
    error_message = "phase1_dh_group_numbers can be 2 or 14 to 24."
  }
  validation {
    condition     = alltrue([for v in(var.tunnel_options.phase2_dh_group_numbers == null ? [] : var.tunnel_options.phase2_dh_group_numbers) : contains([2, 5, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24], v)])
    error_message = "phase2_dh_group_numbers can be 2, 5 or 14 to 24."
  }
  validation {
    condition     = var.tunnel_options.phase1_lifetime_seconds == null ? true : (var.tunnel_options.phase1_lifetime_seconds >= 900 && var.tunnel_options.phase1_lifetime_seconds <= 28800)
    error_message = "phase1_lifetime_seconds must be between 900 and 28800."
  }
  validation {
    condition     = var.tunnel_options.phase2_lifetime_seconds == null ? true : (var.tunnel_options.phase2_lifetime_seconds >= 900 && var.tunnel_options.phase2_lifetime_seconds <= 3600)
    error_message = "phase2_lifetime_seconds must be between 900 and 3600."
  }
  validation {
    condition     = var.tunnel_options.rekey_margin_time_seconds == null ? true : (var.tunnel_options.rekey_margin_time_seconds >= 60 && var.tunnel_options.rekey_margin_time_seconds <= floor((var.tunnel_options.phase2_lifetime_seconds == null ? 3600 : var.tunnel_options.phase2_lifetime_seconds) / 2))
    error_message = "rekey_margin_time_seconds must be between 60 and half of the phase 2 lifetime."
  }
  validation {
    condition     = var.tunnel_options.rekey_fuzz_percentage == null ? true : (var.tunnel_options.rekey_fuzz_percentage >= 0 && var.tunnel_options.rekey_fuzz_percentage <= 100)
    error_message = "rekey_fuzz_percentage must be between 0 and 100."
  }
  validation {
    condition     = var.tunnel_options.replay_window_size == null ? true : (var.tunnel_options.replay_window_size >= 64 && var.tunnel_options.replay_window_size <= 2048)
    error_message = "replay_window_size must be between 64 and 2048."
  }
  validation {
    condition     = var.tunnel_options.dpd_timeout_seconds == null ? true : var.tunnel_options.dpd_timeout_seconds >= 30
    error_message = "dpd_timeout_seconds must be 30 or more."
  }
  validation {
    condition     = var.tunnel_options.dpd_timeout_action == null ? true : contains(["clear", "none", "restart"], var.tunnel_options.dpd_timeout_action)
    error_message = "dpd_timeout_action must be clear, none or restart."
  }
  validation {
    condition     = var.tunnel_options.startup_action == null ? true : contains(["add", "start"], var.tunnel_options.startup_action)
    error_message = "startup_action must be add or start."
  }
}

variable "tunnel1_inside_cidr" {
  type        = string
  description = "Inside /30 CIDR of tunnel 1, from 169.254.0.0/16. Null lets AWS pick."
  default     = null
  validation {
    condition = var.tunnel1_inside_cidr == null ? true : try(
      can(regex("^169\\.254\\.[0-9]{1,3}\\.[0-9]{1,3}/30$", var.tunnel1_inside_cidr)) &&
      cidrhost(var.tunnel1_inside_cidr, 0) == split("/", var.tunnel1_inside_cidr)[0] &&
      !contains(["169.254.0.0/30", "169.254.1.0/30", "169.254.2.0/30", "169.254.3.0/30", "169.254.4.0/30", "169.254.5.0/30", "169.254.169.252/30"], var.tunnel1_inside_cidr),
      false
    )
    error_message = "tunnel1_inside_cidr must be an aligned /30 in 169.254.0.0/16 and not a reserved block."
  }
}

variable "tunnel2_inside_cidr" {
  type        = string
  description = "Inside /30 CIDR of tunnel 2, from 169.254.0.0/16. Null lets AWS pick."
  default     = null
  validation {
    condition = var.tunnel2_inside_cidr == null ? true : try(
      can(regex("^169\\.254\\.[0-9]{1,3}\\.[0-9]{1,3}/30$", var.tunnel2_inside_cidr)) &&
      cidrhost(var.tunnel2_inside_cidr, 0) == split("/", var.tunnel2_inside_cidr)[0] &&
      !contains(["169.254.0.0/30", "169.254.1.0/30", "169.254.2.0/30", "169.254.3.0/30", "169.254.4.0/30", "169.254.5.0/30", "169.254.169.252/30"], var.tunnel2_inside_cidr),
      false
    )
    error_message = "tunnel2_inside_cidr must be an aligned /30 in 169.254.0.0/16 and not a reserved block."
  }
  validation {
    condition     = var.tunnel1_inside_cidr == null || var.tunnel2_inside_cidr == null || var.tunnel1_inside_cidr != var.tunnel2_inside_cidr
    error_message = "tunnel1_inside_cidr and tunnel2_inside_cidr must differ."
  }
}
