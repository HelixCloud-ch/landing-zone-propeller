# network-vpc-hub

Runs in the **network account**, `network` stage (after `account-network`).

Builds the hub VPC of the network plane: a multi-AZ VPC with selectable subnet tiers, centralized internet egress through a regional NAT gateway, an optional internet gateway, and the intra-VPC route tables. The project is deliberately Transit Gateway-agnostic — it owns the VPC and every CIDR inside it, but creates no TGW attachment and no TGW-bound routes.

## VPC and hygiene

The `vpc` module creates the VPC (DNS support and hostnames on), a DHCP options set pinned to AmazonProvidedDNS, and locks down the default security group to no rules so nothing can use it. The internet gateway is optional (`create_internet_gateway`, default `true`); spoke-style VPCs that reach the outside only through the Transit Gateway set it to `false`.

## Subnet tiers

The `subnets` module is the single owner of every subnet CIDR in this VPC. Tiers (`public`, `private`, `tgw`, `resolver`) are selectable and each spans `az_count` Availability Zones. Per tier, CIDRs are either pinned explicitly (a `cidrs` list, one per AZ) or derived from the VPC CIDR with `newbits`/`netnum_base`. Owning all CIDRs in one place is what prevents the overlaps that creep in when sibling projects allocate their own ranges. The `tgw` tier is created but left dormant — it exists so the future `network-vpc-hub-attach` project has a place to put the TGW attachment without renumbering anything.

## Egress (regional NAT)

The `nat` module provisions a single [regional NAT gateway](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-amazon-vpc-regional-nat-gateway/), which operates at VPC level and removes the need for a public subnet per AZ to host NAT. With `nat_availability_zones` empty (default) it runs in auto mode and AWS manages AZ coverage and Elastic IPs; supplying a list pins it to those AZs in manual mode (one EIP per AZ) to cap standing cost, accepting cross-AZ data-transfer charges for workloads in unpinned AZs.

## Routing

The `routing` module creates one route table per tier that has subnets and associates each subnet with it. It writes only the routes this project owns, as single-route `aws_route` resources (never inline `route` blocks) so downstream projects can add routes to the same tables without state conflicts: `0.0.0.0/0` → internet gateway on the public tier (only when the IGW exists) and `0.0.0.0/0` → regional NAT on the private tier. The `tgw` and `resolver` tables carry no default route.

## Operational notes

- **Regional NAT recreate**: switching between auto and manual mode (adding or removing `nat_availability_zones`) recreates the NAT gateway. Plan the change during a maintenance window.
- **No public subnets still means egress works**: regional NAT does not need a public subnet, so disabling the `public` tier leaves private-subnet egress intact. The public tier is only for internet-facing ingress (ALB/NLB).
- **VPC flow logs are deferred** to a tracked issue; the corresponding checkov finding (CKV2_AWS_11) is suppressed inline on the VPC resource with a justification.
- **Single CIDR owner**: downstream projects (`network-vpc-hub-attach`, `network-resolver`) consume subnet IDs from this project's outputs — they must not define new CIDRs inside this VPC.

## What does NOT belong here

- The TGW VPC attachment and any TGW-bound routes — those are `network-vpc-hub-attach`.
- Route 53 Resolver endpoints — those are `network-resolver` (this project only provisions the optional `resolver` subnet tier they consume).
- AWS Network Firewall (`network-firewall`) and Site-to-Site VPN (`network-vpn`).

## References

- [AWS — NAT gateways](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [Introducing Amazon VPC Regional NAT Gateway](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-amazon-vpc-regional-nat-gateway/)
- [AWS — NAT Gateway regional availability (What's new, Nov 2025)](https://aws.amazon.com/about-aws/whats-new/2025/11/aws-nat-gateway-regional-availability/)


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

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_nat"></a> [nat](#module\_nat) | ./modules/nat | n/a |
| <a name="module_routing"></a> [routing](#module\_routing) | ./modules/routing | n/a |
| <a name="module_subnets"></a> [subnets](#module\_subnets) | ./modules/subnets | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ./modules/vpc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_az_count"></a> [az\_count](#input\_az\_count) | Number of Availability Zones the subnet tiers span, bounded by the AZs available in the region. | `number` | `3` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_create_internet_gateway"></a> [create\_internet\_gateway](#input\_create\_internet\_gateway) | Whether to create and attach an internet gateway. Set to false for VPCs that need no direct internet egress (e.g. spoke VPCs reached only via the Transit Gateway). | `bool` | `true` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to the Name tag of every resource (e.g. "network-hub" yields "network-hub-vpc"). | `string` | `"network-hub"` | no |
| <a name="input_nat_availability_zones"></a> [nat\_availability\_zones](#input\_nat\_availability\_zones) | Availability Zones the regional NAT gateway is pinned to (manual mode, one EIP per AZ, lower standing cost). Empty (default) selects auto mode, where AWS manages AZ coverage and EIPs. | `list(string)` | `[]` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the hub VPC (must match the Control Tower home region). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_tiers"></a> [tiers](#input\_tiers) | Map of subnet tier name to its configuration. Enabled tiers create one<br/>subnet per Availability Zone. Per tier, CIDRs come from an explicit `cidrs`<br/>list (one per AZ) when set, otherwise they are derived from vpc\_cidr via<br/>cidrsubnet(vpc\_cidr, newbits, netnum\_base + az\_index). Provide either<br/>`cidrs` or both `newbits` and `netnum_base`. Set map\_public\_ip\_on\_launch<br/>true only for the public tier. The conventional tiers are `public`,<br/>`private`, `tgw`, and `resolver`; the `tgw` tier is reserved (dormant) for<br/>the future network-vpc-hub-attach project. | <pre>map(object({<br/>    enabled                 = bool<br/>    cidrs                   = optional(list(string))<br/>    newbits                 = optional(number)<br/>    netnum_base             = optional(number)<br/>    map_public_ip_on_launch = optional(bool, false)<br/>  }))</pre> | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | IPv4 CIDR block for the hub VPC. Subnet CIDRs are carved from this block when a tier does not specify explicit cidrs. Must be a valid IPv4 CIDR (e.g. 10.0.0.0/16). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | IDs of the private tier subnets (empty when the tier is disabled). |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | IDs of the public tier subnets (empty when the tier is disabled). |
| <a name="output_regional_nat_gateway_id"></a> [regional\_nat\_gateway\_id](#output\_regional\_nat\_gateway\_id) | ID of the regional NAT gateway. |
| <a name="output_regional_nat_route_table_id"></a> [regional\_nat\_route\_table\_id](#output\_regional\_nat\_route\_table\_id) | ID of the route table automatically created by the regional NAT gateway. Consumed by network-spokes to write spoke-CIDR -> TGW return routes so the NAT can route reply packets back to spoke VPCs. |
| <a name="output_resolver_subnet_ids"></a> [resolver\_subnet\_ids](#output\_resolver\_subnet\_ids) | IDs of the resolver tier subnets, consumed by the future network-resolver project (empty when the tier is disabled). |
| <a name="output_route_table_ids"></a> [route\_table\_ids](#output\_route\_table\_ids) | Map of subnet tier name to its route table ID (only tiers that have subnets appear). |
| <a name="output_subnet_ids_by_tier"></a> [subnet\_ids\_by\_tier](#output\_subnet\_ids\_by\_tier) | Map of subnet tier name to its ordered list of subnet IDs. |
| <a name="output_tgw_subnet_ids"></a> [tgw\_subnet\_ids](#output\_tgw\_subnet\_ids) | IDs of the tgw tier subnets, reserved for the future network-vpc-hub-attach project (empty when the tier is disabled). |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | IPv4 CIDR block of the hub VPC. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the hub VPC. |
<!-- END_TF_DOCS -->
