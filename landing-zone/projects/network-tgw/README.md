# network-tgw

Runs in the **Network account**, `network` stage.

Creates the Transit Gateway and its RAM share. This is the anchor resource for the entire network plane — all other network projects reference the TGW ID or the RAM share ARN produced here.

## What it does

**Transit Gateway** — created with the following fixed settings:

- `auto_accept_shared_attachments = "disable"` — required by [Security Hub EC2.23](https://docs.aws.amazon.com/securityhub/latest/userguide/ec2-controls.html#ec2-23) (Severity: High). Prevents cross-account VPC attachments from being accepted without explicit review.
- `default_route_table_association = "disable"` and `default_route_table_propagation = "disable"` — prescribed by [AWS TGW configuration guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/robust-network-design-control-tower/transit-gateway.html): attachments are placed into specific route tables explicitly, not into a shared default.

Route tables and routing policy are managed by downstream projects.

**RAM share** — shares the TGW org-internally so spoke accounts can request VPC attachments. The share is created with no principals; workload OU ARNs are added via `aws_ram_principal_association` during spoke onboarding, using the `share_arn` output.

Requires RAM org-sharing to be enabled in the management account (`org-trusted-access` project).

## What does NOT belong here

- TGW route tables — managed by `network-tgw-routing`.
- RAM principal associations — added per workload OU during spoke onboarding.
- Routes and attachment associations — managed by the project that creates each attachment.

## References

- [AWS Transit Gateway](https://docs.aws.amazon.com/vpc/latest/tgw/what-is-transit-gateway.html)
- [Sharing a Transit Gateway](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-transit-gateways.html#tgw-sharing)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.41.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.41.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ec2_transit_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/ec2_transit_gateway) | resource |
| [aws_ram_resource_association.tgw](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/ram_resource_association) | resource |
| [aws_ram_resource_share.tgw](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/ram_resource_share) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_amazon_side_asn"></a> [amazon\_side\_asn](#input\_amazon\_side\_asn) | Private ASN for the Amazon side of BGP sessions. Must be unique among TGWs that may peer in the same region. | `number` | `64512` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_dns_support"></a> [dns\_support](#input\_dns\_support) | Whether DNS support is enabled on the TGW. Allows VPCs attached to the TGW to resolve public DNS hostnames to private IP addresses across attachments. | `string` | `"enable"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to the TGW and RAM share names (e.g. "network" produces "network-tgw", "network-tgw-share"). | `string` | `"network"` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the Transit Gateway is created (must match the landing zone home region). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_vpn_ecmp_support"></a> [vpn\_ecmp\_support](#input\_vpn\_ecmp\_support) | Whether Equal Cost Multipath (ECMP) routing is enabled for VPN attachments. Allows traffic to be distributed across multiple VPN tunnels to the same destination. | `string` | `"enable"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the Transit Gateway. |
| <a name="output_id"></a> [id](#output\_id) | ID of the Transit Gateway. |
| <a name="output_share_arn"></a> [share\_arn](#output\_share\_arn) | ARN of the RAM share. Downstream projects use this to add aws\_ram\_principal\_association resources when onboarding workload OUs. |
<!-- END_TF_DOCS -->
