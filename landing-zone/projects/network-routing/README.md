# network-routing

Runs in the **network account**, `network` stage (after `network-tgw`,
`network-vpc-hub`, and `network-s2s`).

Central routing for the network plane. This is the single project that decides
how traffic moves between the hub VPC, on-premises (via the Site-to-Site VPN),
and — later — spokes. It owns the Transit Gateway route table, the attachment
associations, and the routes; the attachment-owning projects own only their
attachments. Keeping all routing in one place is what lets the whole TGW
route-table state be reviewed in a single plan.

## Why the hub TGW attachment lives here (for now)

Per the agreed design, the hub TGW VPC attachment belongs in `network-vpc-hub`
(option A). During this first end-to-end routing test it is created here instead,
because `network-vpc-hub` is a framework project and the consumer override system
cannot add a `tgw_id` input or an attachment output to a base-pipeline step. The
attachment relocates into `network-vpc-hub` at promotion, when wiring the input
and output on the base step is trivial. The attachment reads the hub's dormant
`tgw`-tier subnet IDs, so no renumbering is needed when it moves.

## Routing model

Routing policy is **declarative input**, not inferred. The project does not
assume that on-prem traffic must traverse a firewall or land on the hub VPC — it
writes exactly the routes it is given:

- **TGW route table**: one table for the test topology, with the hub attachment
  and every VPN attachment associated to it. The TGW has default
  association/propagation disabled, so membership is explicit.
- **Static TGW routes**: the hub VPC CIDR points at the hub attachment; each
  on-prem CIDR points at the VPN attachment. Static (not propagated) because
  `network-s2s` runs the VPN with `static_routes_only = true` (no BGP).
- **Hub VPC return route**: each on-prem CIDR is routed to the TGW from the hub
  private route table, as a single-route `aws_route` so `network-vpc-hub` keeps
  owning its own `0.0.0.0/0` routes on the same table.

## Operational notes

- **On-prem CIDRs are customer values.** They live only in the consumer
  `config.auto.tfvars` and currently use an RFC 5737 placeholder
  (`192.0.2.0/24`) until the real ranges are known.
- **Hub private route table lookup.** `network-vpc-hub` does not publish its
  route table IDs to SSM, so the on-prem return route locates the hub private
  table by its Name tag (`<hub_name_prefix>-private-rt`). Pass
  `hub_private_route_table_id` explicitly if the hub used a non-default
  `name_prefix`.
- **End-to-end ping prerequisites** (outside this project): real on-prem peer IP
  in `network-s2s`, the customer device configured from the s2s `tunnel_details`
  output, an EC2 instance in a hub private subnet, and a security group allowing
  ICMP from the on-prem CIDR.

## What does NOT belong here

- The TGW itself and its RAM share — `network-tgw`.
- The hub VPC, its subnets, NAT, and intra-VPC `0.0.0.0/0` routes —
  `network-vpc-hub`.
- The customer gateway, VPN connection, and tunnels — `network-s2s`.
- Spoke VPC attachments and spoke acceptance — future `network-spoke-accept`.
- Per-segment TGW route tables (Spokes/Hub split) — a later extension of this
  project.

## References

- [AWS — Transit Gateway route tables](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-route-tables.html)
- [AWS — Transit Gateway design best practices](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-best-design-practices.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.49.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.49.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ec2_transit_gateway_route.hub_cidr](https://registry.terraform.io/providers/hashicorp/aws/6.49.0/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_route.onprem](https://registry.terraform.io/providers/hashicorp/aws/6.49.0/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_route_table.main](https://registry.terraform.io/providers/hashicorp/aws/6.49.0/docs/resources/ec2_transit_gateway_route_table) | resource |
| [aws_ec2_transit_gateway_route_table_association.hub](https://registry.terraform.io/providers/hashicorp/aws/6.49.0/docs/resources/ec2_transit_gateway_route_table_association) | resource |
| [aws_ec2_transit_gateway_route_table_association.vpn](https://registry.terraform.io/providers/hashicorp/aws/6.49.0/docs/resources/ec2_transit_gateway_route_table_association) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.hub](https://registry.terraform.io/providers/hashicorp/aws/6.49.0/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_route.hub_to_onprem](https://registry.terraform.io/providers/hashicorp/aws/6.49.0/docs/resources/route) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_hub_route_table_ids"></a> [hub\_route\_table\_ids](#input\_hub\_route\_table\_ids) | JSON-encoded map of subnet tier name to route table ID for the hub VPC, from the network-vpc-hub blob (route\_table\_ids). Used to add the on-prem return route to the private tier's route table. | `string` | n/a | yes |
| <a name="input_hub_tgw_subnet_ids"></a> [hub\_tgw\_subnet\_ids](#input\_hub\_tgw\_subnet\_ids) | JSON-encoded list of hub VPC tgw-tier subnet IDs (one per AZ), from the network-vpc-hub blob (tgw\_subnet\_ids). The hub TGW VPC attachment places its ENIs in these subnets. | `string` | n/a | yes |
| <a name="input_hub_vpc_cidr"></a> [hub\_vpc\_cidr](#input\_hub\_vpc\_cidr) | Hub VPC IPv4 CIDR, from network-vpc-hub (/network.vpc.cidr). Advertised to on-prem via the TGW route table. | `string` | n/a | yes |
| <a name="input_hub_vpc_id"></a> [hub\_vpc\_id](#input\_hub\_vpc\_id) | Hub VPC ID, from network-vpc-hub (/network.vpc.id). Used to attach the hub VPC to the TGW and to locate the hub private route table. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to the Name tag of every resource (e.g. "network" yields "network-spokes-rt"). | `string` | `"network"` | no |
| <a name="input_onprem_cidrs"></a> [onprem\_cidrs](#input\_onprem\_cidrs) | On-premises IPv4 CIDR blocks reachable through the Site-to-Site VPN. Each is<br/>added to the TGW route table as a static route pointing at the VPN<br/>attachment, and to the hub VPC private route table pointing at the TGW.<br/>These are customer values and live only in the consumer config. | `list(string)` | `[]` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the network plane (must match the Control Tower home region). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_tgw_id"></a> [tgw\_id](#input\_tgw\_id) | Transit Gateway ID, from network-tgw (/network.tgw.id). | `string` | n/a | yes |
| <a name="input_vpn_attachment_ids"></a> [vpn\_attachment\_ids](#input\_vpn\_attachment\_ids) | JSON-encoded map of on-prem peer IP to TGW VPN attachment ID, from the network-s2s blob (vpn\_attachment\_ids). Pass an empty string or '{}' when network-s2s has not been applied yet. | `string` | `"{}"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_hub_attachment_id"></a> [hub\_attachment\_id](#output\_hub\_attachment\_id) | ID of the hub VPC TGW attachment. |
| <a name="output_onprem_cidrs"></a> [onprem\_cidrs](#output\_onprem\_cidrs) | On-premises IPv4 CIDR blocks routed through the Site-to-Site VPN. Consumed by downstream projects (e.g. network-resolver SG rules, network-firewall policy). |
| <a name="output_tgw_route_table_id"></a> [tgw\_route\_table\_id](#output\_tgw\_route\_table\_id) | ID of the TGW route table this project owns. |
<!-- END_TF_DOCS -->