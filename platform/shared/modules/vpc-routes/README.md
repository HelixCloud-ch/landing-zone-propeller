# vpc-routes module

Creates VPC route tables, subnet associations, and routes from explicit,
already-resolved input.

## Scope

The module deals only in plain AWS data: route tables keyed by an arbitrary key,
associations naming a route table key and a subnet ID, and routes naming a route
table key, a destination CIDR, and exactly one `aws_route` target argument.

It knows nothing about subnet tiers, symbolic target names, or which argument a
given resource ID implies. That correlation is the caller's job — see the
`vpc-routes` project for how propeller's inputs are translated. Keeping it out
means this module works unchanged under a different pipeline, or a bare
`terraform apply`.

## Usage

```hcl
module "routes" {
  source = "../../../shared/modules/vpc-routes"

  vpc_id = "vpc-0123456789abcdef0"

  route_tables = {
    public = { name = "example-public-rt" }
    app    = { name = "example-app-rt" }
  }

  associations = {
    "public-0" = { route_table_key = "public", subnet_id = "subnet-0aaa1" }
    "app-0"    = { route_table_key = "app", subnet_id = "subnet-0bbb1" }
  }

  routes = {
    "public-0.0.0.0/0" = {
      route_table_key        = "public"
      destination_cidr_block = "0.0.0.0/0"
      gateway_id             = "igw-0123456789abcdef0"
    }
    "app-0.0.0.0/0" = {
      route_table_key        = "app"
      destination_cidr_block = "0.0.0.0/0"
      nat_gateway_id         = "nat-0123456789abcdef0"
    }
  }
}
```

Map keys become Terraform instance keys, so choose them to be stable across
plans — they determine the resource addresses.

## Target arguments

Each `routes` entry sets exactly one of `carrier_gateway_id`, `core_network_arn`,
`egress_only_gateway_id`, `gateway_id`, `local_gateway_id`, `nat_gateway_id`,
`network_interface_id`, `transit_gateway_id`, `vpc_endpoint_id`,
`vpc_peering_connection_id`. Setting none or several fails at plan time.

`gateway_id` is only for an internet gateway or a virtual private gateway. The
AWS API also accepts a NAT gateway ID there, but returns the more specific
attribute, which shows up as a permanent diff — use `nat_gateway_id`. See the
[`aws_route` documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route).

Validated at plan time: every `route_table_key` exists in `route_tables`, every
destination is a valid IPv4 CIDR, exactly one target per route, and no two routes
share a route table and destination.

## What does NOT belong here

- Creating gateways. Callers pass IDs of gateways owned elsewhere.
- Gateway VPC endpoint prefix-list routes for S3 or DynamoDB. Use
  `aws_vpc_endpoint_route_table_association` instead. `vpc_endpoint_id` here is
  for a Gateway Load Balancer endpoint used as a route target in a subnet
  route table (egress inspection). The ingress half — an IGW edge association
  (`gateway_id` on `aws_route_table_association`) — is not modelled; see the
  backlog for the deferral rationale.
- Provider configuration and tagging beyond the Name tag. The calling project
  owns the provider and its `default_tags`.
- IPv6 routes. Only `destination_cidr_block` is wired; add
  `destination_ipv6_cidr_block` when a consumer needs it.

## References

- [aws_route](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route)
- [aws_route_table](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table)
- [aws_route_table_association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association)
