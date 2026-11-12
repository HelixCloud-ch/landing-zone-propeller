output "vpn_connection_ids" {
  description = "VPN connection IDs, keyed by connection key."
  value       = { for k, m in module.connection : k => m.id }
}

output "vpn_connection_arns" {
  description = "VPN connection ARNs, keyed by connection key."
  value       = { for k, m in module.connection : k => m.arn }
}

output "transit_gateway_attachment_ids" {
  description = "Transit gateway VPN attachment IDs, keyed by connection key. Only connections on a transit gateway."
  value       = { for k, m in module.connection : k => m.transit_gateway_attachment_id if local.connection_target_types[k] == "tgw" }
}

output "connection_targets" {
  description = "Target of each connection, keyed by connection key: type (tgw, vgw or none) and gateway_id."
  value = {
    for k, t in local.connection_target_types : k => {
      type       = t
      gateway_id = local.connection_target_gateway_ids[k] == null ? "" : local.connection_target_gateway_ids[k]
    }
  }
}

output "tunnels" {
  description = "Tunnel addresses, inside addresses and BGP ASN, keyed by connection key."
  value       = { for k, m in module.connection : k => m.tunnels }
}

output "preshared_key_arns" {
  description = "Secrets Manager ARNs of the pre-shared keys, keyed by connection key. Only for SecretsManager storage."
  value       = { for k, m in module.connection : k => m.preshared_key_arn if var.connections[k].preshared_key_storage == "SecretsManager" }
}

output "customer_gateway_ids" {
  description = "IDs of the created customer gateways, keyed by customer gateway key."
  value       = { for k, c in aws_customer_gateway.this : k => c.id }
}

output "vpn_gateway_ids" {
  description = "IDs of the virtual private gateways (created or given), keyed by vpn_gateways key."
  value       = local.vgw_ids
}
