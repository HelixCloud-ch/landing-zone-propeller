# network-s2s

Site-to-Site VPN connection(s) from on-premises networks to the AWS Transit Gateway, with static routing. Runs in the network account.

## What it does

Creates AWS Site-to-Site VPN infrastructure for connecting on-premises networks to the Transit Gateway:

- **Customer Gateway(s)**: One or two customer gateways representing on-prem VPN endpoints
- **VPN Connection(s)**: IPsec VPN connections attached to the Transit Gateway with static routing
  - Single CGW topology: 1 VPN connection → 2 tunnels
  - Dual CGW topology: 2 VPN connections → 4 tunnels (high availability)
- **Outputs**: On-prem CIDRs exposed as Terraform output (autopilot stores in Parameter Store for routing projects)

## What it does NOT do

- **No BGP**: Uses static routing exclusively (`static_routes_only = true`)
- **No TGW route table routes**: Routes on TGW Spokes RT and Hub RT are created by a separate routing project.
- **No VPC routes**: Hub VPC routes to on-prem are created by a separate routing project
- **No prefix lists**: Avoids `pl-onprem` to prevent route table slot over-allocation

## Topology Options

### Single Customer Gateway (2 tunnels)

One on-prem edge router with a single public IP.

```
On-prem Edge Router ─┬─ Tunnel 1 ─┐
  (203.0.113.1)      └─ Tunnel 2 ─┼─ TGW VPN Attachment
```

### Dual Customer Gateway (4 tunnels)

Two on-prem edge routers for high availability.

```
On-prem Edge Router 1 ─┬─ Tunnel 1 ─┐
  (203.0.113.1)        └─ Tunnel 2 ─┤
                                     ├─ TGW VPN Attachment
On-prem Edge Router 2 ─┬─ Tunnel 3 ─┤
  (203.0.113.2)        └─ Tunnel 4 ─┘
```

## Configuration Examples

### Single CGW

```hcl
tgw_id               = "tgw-0abc123"
customer_gateway_ips = ["203.0.113.1"]
onprem_cidrs         = ["10.0.0.0/8", "172.16.0.0/12"]
name_prefix          = "network-s2s"
```

### Dual CGW

```hcl
tgw_id               = "tgw-0abc123"
customer_gateway_ips = ["203.0.113.1", "203.0.113.2"]
onprem_cidrs         = ["10.0.0.0/8", "172.16.0.0/12"]
name_prefix          = "network-s2s"
```

## Operational Notes

### VPN Configuration

After `terraform apply`:

1. Retrieve tunnel configuration from the `tunnel_details` output (marked sensitive)
2. Configure your on-prem customer gateway device(s) with:
   - Tunnel endpoint IPs (AWS public IPs from `tunnel1_address`, `tunnel2_address`)
   - Inside CIDR addresses for BGP peering (even though BGP is disabled, these are used for tunnel interfaces)
   - Pre-shared keys
3. Ensure on-prem firewall allows UDP 500 (IKE) and IP protocol 50 (ESP) from AWS tunnel IPs

### Static Routes

With TGW as the VPN target, on-prem static routes are managed via `aws_ec2_transit_gateway_route` on the TGW route tables — **not** via `aws_vpn_connection_route` (which is VGW-only and fails at apply when `transit_gateway_id` is set). This project sets `static_routes_only = true` on the VPN connection to disable BGP; the actual TGW route entries are created by the separate routing project using the `onprem_cidrs` output.

### High Availability

Dual CGW topology provides redundancy:

- If one on-prem edge router fails, traffic continues through the other
- AWS automatically manages tunnel health monitoring
- Both VPN connections must have identical static route configuration (automatically ensured by Terraform)

## Cross-references


- [AWS Site-to-Site VPN Documentation](https://docs.aws.amazon.com/vpn/latest/s2svpn/)
- [TGW VPN Attachments](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpn-attachments.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.49 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.49 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_customer_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/customer_gateway) | resource |
| [aws_vpn_connection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_customer_gateway_ips"></a> [customer\_gateway\_ips](#input\_customer\_gateway\_ips) | List of on-premises customer gateway public IP addresses. Single IP creates<br/>one VPN connection with 2 tunnels. Two IPs create two VPN connections with<br/>4 tunnels total (high availability topology). | `list(string)` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to the Name tag of every resource (e.g. "network-s2s" yields "network-s2s-cgw-0"). | `string` | n/a | yes |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the Site-to-Site VPN resources are created. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_tgw_id"></a> [tgw\_id](#input\_tgw\_id) | ID of the Transit Gateway to which the VPN connection(s) are attached. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_customer_gateway_ids"></a> [customer\_gateway\_ids](#output\_customer\_gateway\_ids) | Map of customer gateway IP to customer gateway ID. |
| <a name="output_tunnel_details"></a> [tunnel\_details](#output\_tunnel\_details) | VPN tunnel details for each connection (public IPs, inside addresses, pre-shared keys). Sensitive. |
| <a name="output_vpn_attachment_ids"></a> [vpn\_attachment\_ids](#output\_vpn\_attachment\_ids) | Map of customer gateway IP to Transit Gateway VPN attachment ID. |
| <a name="output_vpn_connection_ids"></a> [vpn\_connection\_ids](#output\_vpn\_connection\_ids) | Map of customer gateway IP to VPN connection ID. |
<!-- END_TF_DOCS -->
