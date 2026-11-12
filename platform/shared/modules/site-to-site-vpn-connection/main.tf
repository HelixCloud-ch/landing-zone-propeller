locals {
  logs_enabled = var.log_group_arn != null || var.bgp_log_group_arn != null
}

resource "aws_vpn_connection" "this" {
  type                = "ipsec.1"
  customer_gateway_id = var.customer_gateway_id
  transit_gateway_id  = var.target_type == "tgw" ? var.target_gateway_id : null
  vpn_gateway_id      = var.target_type == "vgw" ? var.target_gateway_id : null
  static_routes_only  = var.routing == "static"

  tunnel_bandwidth         = var.tunnel_bandwidth
  enable_acceleration      = var.enable_acceleration
  local_ipv4_network_cidr  = var.local_ipv4_network_cidr
  remote_ipv4_network_cidr = var.remote_ipv4_network_cidr
  preshared_key_storage    = var.preshared_key_storage

  tunnel1_inside_cidr                     = var.tunnel1_inside_cidr
  tunnel1_ike_versions                    = var.tunnel_options.ike_versions
  tunnel1_phase1_encryption_algorithms    = var.tunnel_options.phase1_encryption_algorithms
  tunnel1_phase2_encryption_algorithms    = var.tunnel_options.phase2_encryption_algorithms
  tunnel1_phase1_integrity_algorithms     = var.tunnel_options.phase1_integrity_algorithms
  tunnel1_phase2_integrity_algorithms     = var.tunnel_options.phase2_integrity_algorithms
  tunnel1_phase1_dh_group_numbers         = var.tunnel_options.phase1_dh_group_numbers
  tunnel1_phase2_dh_group_numbers         = var.tunnel_options.phase2_dh_group_numbers
  tunnel1_phase1_lifetime_seconds         = var.tunnel_options.phase1_lifetime_seconds
  tunnel1_phase2_lifetime_seconds         = var.tunnel_options.phase2_lifetime_seconds
  tunnel1_rekey_margin_time_seconds       = var.tunnel_options.rekey_margin_time_seconds
  tunnel1_rekey_fuzz_percentage           = var.tunnel_options.rekey_fuzz_percentage
  tunnel1_replay_window_size              = var.tunnel_options.replay_window_size
  tunnel1_dpd_timeout_seconds             = var.tunnel_options.dpd_timeout_seconds
  tunnel1_dpd_timeout_action              = var.tunnel_options.dpd_timeout_action
  tunnel1_startup_action                  = var.tunnel_options.startup_action
  tunnel1_enable_tunnel_lifecycle_control = var.tunnel_options.enable_tunnel_lifecycle_control

  tunnel2_inside_cidr                     = var.tunnel2_inside_cidr
  tunnel2_ike_versions                    = var.tunnel_options.ike_versions
  tunnel2_phase1_encryption_algorithms    = var.tunnel_options.phase1_encryption_algorithms
  tunnel2_phase2_encryption_algorithms    = var.tunnel_options.phase2_encryption_algorithms
  tunnel2_phase1_integrity_algorithms     = var.tunnel_options.phase1_integrity_algorithms
  tunnel2_phase2_integrity_algorithms     = var.tunnel_options.phase2_integrity_algorithms
  tunnel2_phase1_dh_group_numbers         = var.tunnel_options.phase1_dh_group_numbers
  tunnel2_phase2_dh_group_numbers         = var.tunnel_options.phase2_dh_group_numbers
  tunnel2_phase1_lifetime_seconds         = var.tunnel_options.phase1_lifetime_seconds
  tunnel2_phase2_lifetime_seconds         = var.tunnel_options.phase2_lifetime_seconds
  tunnel2_rekey_margin_time_seconds       = var.tunnel_options.rekey_margin_time_seconds
  tunnel2_rekey_fuzz_percentage           = var.tunnel_options.rekey_fuzz_percentage
  tunnel2_replay_window_size              = var.tunnel_options.replay_window_size
  tunnel2_dpd_timeout_seconds             = var.tunnel_options.dpd_timeout_seconds
  tunnel2_dpd_timeout_action              = var.tunnel_options.dpd_timeout_action
  tunnel2_startup_action                  = var.tunnel_options.startup_action
  tunnel2_enable_tunnel_lifecycle_control = var.tunnel_options.enable_tunnel_lifecycle_control

  dynamic "tunnel1_log_options" {
    for_each = local.logs_enabled ? [1] : []
    content {
      cloudwatch_log_options {
        log_enabled           = var.log_group_arn != null
        log_group_arn         = var.log_group_arn
        log_output_format     = var.log_group_arn != null ? "json" : null
        bgp_log_enabled       = var.bgp_log_group_arn != null
        bgp_log_group_arn     = var.bgp_log_group_arn
        bgp_log_output_format = var.bgp_log_group_arn != null ? "json" : null
      }
    }
  }

  dynamic "tunnel2_log_options" {
    for_each = local.logs_enabled ? [1] : []
    content {
      cloudwatch_log_options {
        log_enabled           = var.log_group_arn != null
        log_group_arn         = var.log_group_arn
        log_output_format     = var.log_group_arn != null ? "json" : null
        bgp_log_enabled       = var.bgp_log_group_arn != null
        bgp_log_group_arn     = var.bgp_log_group_arn
        bgp_log_output_format = var.bgp_log_group_arn != null ? "json" : null
      }
    }
  }

  tags = {
    Name = var.name
  }
}

resource "aws_vpn_connection_route" "this" {
  for_each = toset(var.static_routes)

  vpn_connection_id      = aws_vpn_connection.this.id
  destination_cidr_block = each.value
}

check "unassociated_target" {
  data "aws_vpn_connection" "current" {
    vpn_connection_id = aws_vpn_connection.this.id
  }

  assert {
    condition = var.target_type != "none" || (
      (data.aws_vpn_connection.current.transit_gateway_id == null || data.aws_vpn_connection.current.transit_gateway_id == "") &&
      (data.aws_vpn_connection.current.vpn_gateway_id == null || data.aws_vpn_connection.current.vpn_gateway_id == "")
    )
    error_message = "The connection is configured as unassociated but AWS still shows a target gateway. AWS cannot detach a target: recreate the connection (new tunnel IPs and pre-shared keys)."
  }
}
