# workload-vpc

Runs in a **workload account** (e.g. `test-acc-1`) via a platform pipeline. Builds the workload VPC and attaches it to the landing-zone Transit Gateway. Reachability across the TGW is decided by `network-spokes` in the network account; this project only owns the VPC, its subnets, the intra-VPC route tables, and the TGW VPC attachment.

See [ADR-009](../../../../../notes/wiki/decisions/ADR-009-workload-vpc-platform.md) for the design rationale.

## VPC and hygiene

The `vpc` module creates the VPC (DNS support and hostnames on), a DHCP options set pinned to AmazonProvidedDNS, and locks the default security group down to no rules. No internet gateway is attached: workload egress goes through the hub VPC's regional NAT via the TGW.

## Subnet tiers

The `subnets` module owns every CIDR inside this VPC. Three tiers are provisioned, each spanning `az_count` AZs:

- **`app`** — workload compute (ECS tasks, EC2, Lambda ENIs).
- **`data`** — persistence layer (RDS, ElastiCache, etc.).
- **`tgw-attach`** — minimal `/28` per AZ for the TGW VPC attachment ENIs, per AWS guidance ([Transit Gateway design best practices](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-best-design-practices.html)).

CIDRs are pinned explicitly per tier. The test instance uses `/28` per AZ across the board, all carved from `10.16.0.0/24` to keep the test allocation minimal. The full `/16` `10.16.0.0/16` is reserved in the CIDR plan for this account and can be used once the workload graduates to production.

### Subnet extra tags

Each tier accepts an `extra_tags` map that is merged onto every subnet in the tier. This is the hook for controller-discovery tags:

```hcl
# EKS AWS Load Balancer Controller — internal LB discovery
app = {
  enabled = true
  cidrs   = ["..."]
  extra_tags = {
    "kubernetes.io/role/internal-elb"      = "1"
    "kubernetes.io/cluster/my-cluster"     = "shared"
  }
}
```

For an external-facing ALB tier (not present in the current config), use `kubernetes.io/role/elb = "1"` instead. These tags have no effect until an EKS cluster and the AWS LBC are deployed; leaving them unset is safe.

## TGW attachment

The `tgw-attach` module creates a single `aws_ec2_transit_gateway_vpc_attachment` against the RAM-shared TGW (`var.tgw_id`, delivered through `@landing-zone/workload-parameters.tgw_id`). The attachment lands in `pendingAcceptance` until `network-spokes` accepts it.

`transit_gateway_default_route_table_association` and `transit_gateway_default_route_table_propagation` are deliberately omitted — the [resource docs](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/ec2_transit_gateway_vpc_attachment) state these "cannot be configured or perform drift detection with Resource Access Manager shared EC2 Transit Gateways." The TGW owner (`network-spokes`) controls associations and propagations.

## Routing

The `routing` module creates one route table per tier and associates each subnet with its tier's table. The default route is written as a single-route resource (`aws_route`) to leave room for siblings to add routes without state conflicts:

| Tier         | Default route                          |
|--------------|----------------------------------------|
| `app`        | `0.0.0.0/0 → TGW attachment`           |
| `data`       | `0.0.0.0/0 → TGW attachment`           |
| `tgw-attach` | none — local-VPC routing only          |

Anything not local goes to the TGW. From there, the TGW route table that `network-spokes` associated with this attachment decides the rest; unmatched destinations are dropped (effective blackhole).

## Pipeline usage

```yaml
- project: workload-vpc
  target: test-acc-1
  inputs:
    - name: "@landing-zone/workload-parameters.tgw_id"
      var: tgw_id
  outputs:
    - name: vpc_id
    - name: vpc_cidr
    - name: tgw_attachment_id
    - name: subnet_ids_by_tier
```

After this platform applies, the bring-up sequence continues in the landing-zone pipeline:

1. Register the spoke in `landing-zone-propeller-internal/landing-zone/projects/network-spokes/terraform/config.auto.tfvars` with the `attachment_id`, `cidrs = ["10.16.0.0/16"]`, a chosen `segment`, and an `allowed_destinations` list.
2. Re-apply the landing zone (`network-spokes` step). The attachment moves to `available`; per-segment routes are written.
3. Verify connectivity from a test EC2 instance in the `app` tier.

## What does NOT belong here

- TGW route table association / propagation — owned by `network-spokes`.
- Spoke reachability routes (to hub, on-prem, peer spokes) — same.
- Any IGW / NAT / direct internet egress — by design, egress is through the hub.
- Workload-specific resources (ECS clusters, RDS instances, application security groups). Those belong in downstream platform pipelines that consume `vpc_id` / `subnet_ids_by_tier`.

## References

- [ADR-007: Network Plane Design](../../../../../notes/wiki/decisions/ADR-007-network-plane-design.md)
- [ADR-009: Workload VPC Platform Pipeline](../../../../../notes/wiki/decisions/ADR-009-workload-vpc-platform.md)
- [AWS — Transit Gateway design best practices](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-best-design-practices.html)
- [AWS — Amazon VPC attachments in AWS Transit Gateway](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpc-attachments.html)
- [Terraform — `aws_ec2_transit_gateway_vpc_attachment`](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/ec2_transit_gateway_vpc_attachment)
