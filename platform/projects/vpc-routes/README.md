# vpc-routes

Runs in a workload account. Creates one route table per subnet tier, associates
that tier's subnets, and installs the routes declared by `tier_routes`.

## Routing policy

`tier_routes` is a map from tier name to a list of route entries. Each entry
declares a `destination` (IPv4 CIDR) and exactly one typed target field:

| Field | Resolves to | ID variable |
|---|---|---|
| `igw = true` | the VPC's Internet Gateway | `igw_id` |
| `vgw = true` | the VPC's Virtual Private Gateway | `vgw_id` |
| `tgw_key` | a Transit Gateway by key | `tgw_ids["<key>"]` |
| `natgw_key` | a NAT Gateway by key | `natgw_ids["<key>"]` |
| `peering_key` | a VPC peering connection by key | `peering_ids["<key>"]` |
| `vpce_key` | a GWLB endpoint by key | `vpc_endpoint_ids["<key>"]` |
| `target_key` | any other target by key (escape hatch) | `route_targets["<key>"]` |

Setting zero or more than one target field fails the plan.

```hcl
tier_routes = {
  public = [{ destination = "0.0.0.0/0", igw = true }]
  app = [
    { destination = "0.0.0.0/0", natgw_key = "regional" },
    { destination = "10.0.0.0/8", tgw_key = "main" },
  ]
  data = [
    { destination = "0.0.0.0/0", tgw_key = "main" },
  ]
}
```

A tier may declare several routes — split egress (internet via NAT, private
ranges via TGW) needs exactly that and cannot be expressed as one default route.
A tier with no entry still gets a route table and associations, just no routes
beyond the implicit `local` one. A tier with no subnets is skipped entirely.

## Target ID variables

Gateway IDs and the routing policy are deliberately separated. `tier_routes`
lives in `config.auto.tfvars` — static, committed, written by hand. Gateway IDs
are runtime values that arrive as pipeline inputs. `tier_routes` therefore refers
to targets by typed field, not by raw ID, so nobody has to paste a `nat-…` into
a tfvars file where it would go stale on the next rebuild.

| Variable | Provides | Multiplicity |
|---|---|---|
| `igw_id` | Internet Gateway | one per VPC (AWS limit) |
| `vgw_id` | Virtual Private Gateway | one per VPC (AWS limit) |
| `tgw_ids` | Transit Gateways by key | up to 5 per VPC |
| `natgw_ids` | NAT Gateways by key | many |
| `peering_ids` | VPC peering connections by key | many |
| `vpc_endpoint_ids` | GWLB endpoints by key | many |
| `route_targets` | escape hatch, any ID | many |

For `route_targets`, the `aws_route` argument is derived from the ID prefix
(`igw-`/`vgw-` → `gateway_id`, `nat-` → `nat_gateway_id`, `tgw-` →
`transit_gateway_id`, `pcx-` → `vpc_peering_connection_id`, `vpce-` →
`vpc_endpoint_id`, `eigw-` → `egress_only_gateway_id`, `eni-` →
`network_interface_id`, `cagw-` → `carrier_gateway_id`, `lgw-` →
`local_gateway_id`, `arn:` → `core_network_arn`). An unrecognized prefix fails
the plan.

## `vpce_key` and inspection

`vpce_key` covers a Gateway Load Balancer endpoint used as a route target in a
subnet route table (egress inspection). The ingress half of the centralized
inspection pattern — an IGW edge association (`gateway_id` on
`aws_route_table_association`) — is not modelled; see the backlog for the
deferral rationale.

Gateway endpoints for S3 and DynamoDB are *not* routed here — the `vpc-endpoints`
project owns those via `aws_vpc_endpoint_route_table_association`.

## TGW attachment readiness

This project does not gate on TGW attachment state. If a TGW route is configured
and the attachment has not yet been accepted (`pendingAcceptance`), the
`aws_route` apply will fail with an AWS API error. In supervised mode the
pipeline pauses, the network team accepts via `network-spokes`, and the step is
retried.

## State migration (`moved` blocks)

The resources now live in `shared/modules/vpc-routes`, so their addresses gain a
`module.routes.` prefix. Route tables and associations keep their instance keys,
so the generic blocks in `terraform/moved.tf` cover them for every consumer.
Routes also changed key scheme — from tier-only to `<tier>-<destination>` — and a
`moved` block cannot remap instance keys, so each consumer adds one block per
tier that previously had routes:

```hcl
# platforms/<platform>/projects/vpc-routes/terraform/moved.tf
moved {
  from = aws_route.tgw_default["app"]
  to   = module.routes.aws_route.this["app-0.0.0.0/0"]
}
```

Verify with a plan against a copy of the real state; it should report moves and
zero destroys. The `route_keys` output lists the new keys.

## What does NOT belong here

- Creating gateways. The IGW, NAT gateways, TGW attachment, peering connections
  and endpoints are owned by other projects; this one only routes to them.
- Accepting the TGW attachment or writing TGW route tables — that is
  `network-spokes`, in the network account.
- IPv6 routes. Only `destination_cidr_block` is wired; add
  `destination_ipv6_cidr_block` when a consumer needs it.

## References

- [aws_route](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route)
- [Amazon VPC quotas](https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html)
- [Transit Gateway quotas](https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html)
- [Access virtual appliances through AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/vpce-gateway-load-balancer.html)
- [Terraform moved blocks](https://developer.hashicorp.com/terraform/language/moved)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.41 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_routes"></a> [routes](#module\_routes) | ../../../shared/modules/vpc-routes | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.targets_resolved](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_igw_id"></a> [igw\_id](#input\_igw\_id) | Internet Gateway ID, from vpc-igw.igw\_id. Referenced by `igw = true`. | `string` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix used for route table Name tags (must match the value used in the vpc project). | `string` | `"test1-vpc"` | no |
| <a name="input_natgw_ids"></a> [natgw\_ids](#input\_natgw\_ids) | NAT Gateway IDs by key. Referenced by `natgw_key`. | `map(string)` | `{}` | no |
| <a name="input_peering_ids"></a> [peering\_ids](#input\_peering\_ids) | VPC peering connection IDs by key. Referenced by `peering_key`. | `map(string)` | `{}` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region (must match the vpc project region). | `string` | n/a | yes |
| <a name="input_route_targets"></a> [route\_targets](#input\_route\_targets) | Extra targets by key, for types with no dedicated variable (ENI, carrier<br/>gateway, Outpost local gateway, Cloud WAN core network ARN). Referenced by<br/>`target_key`. The aws\_route argument is derived from the ID prefix. | `map(string)` | `{}` | no |
| <a name="input_subnet_ids_by_tier"></a> [subnet\_ids\_by\_tier](#input\_subnet\_ids\_by\_tier) | Map of tier name to ordered subnet ID list, from vpc.subnet\_ids\_by\_tier. | `map(list(string))` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_tgw_ids"></a> [tgw\_ids](#input\_tgw\_ids) | Transit Gateway IDs by key. Referenced by `tgw_key`. AWS allows up to 5 TGW attachments per VPC. | `map(string)` | `{}` | no |
| <a name="input_tier_routes"></a> [tier\_routes](#input\_tier\_routes) | Per-tier routes. Each entry sets exactly one target field. `destination` is<br/>an IPv4 CIDR. See README for the target field semantics. | <pre>map(list(object({<br/>    destination = string<br/>    igw         = optional(bool)<br/>    vgw         = optional(bool)<br/>    tgw_key     = optional(string)<br/>    natgw_key   = optional(string)<br/>    peering_key = optional(string)<br/>    vpce_key    = optional(string)<br/>    target_key  = optional(string)<br/>  })))</pre> | `{}` | no |
| <a name="input_vgw_id"></a> [vgw\_id](#input\_vgw\_id) | Virtual Private Gateway ID. Referenced by `vgw = true`. | `string` | `null` | no |
| <a name="input_vpc_endpoint_ids"></a> [vpc\_endpoint\_ids](#input\_vpc\_endpoint\_ids) | VPC endpoint IDs by key, for Gateway Load Balancer endpoints used as a<br/>route target. Referenced by `vpce_key`. Gateway endpoints (S3, DynamoDB)<br/>do not belong here. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC, from vpc.vpc\_id. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_route_keys"></a> [route\_keys](#output\_route\_keys) | Keys of the created routes ("<tier>-<destination>"). Needed when writing moved blocks or import commands. |
| <a name="output_route_table_ids"></a> [route\_table\_ids](#output\_route\_table\_ids) | Map of tier name to route table ID for all tiers that have subnets. |
<!-- END_TF_DOCS -->
