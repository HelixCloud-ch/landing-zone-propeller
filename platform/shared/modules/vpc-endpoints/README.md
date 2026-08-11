# vpc-endpoints

Shared Terraform module for VPC Interface and Gateway endpoints. Used by the
`workload-vpc-endpoints` platform project (and available to any project that
needs private connectivity to AWS service APIs without routing through NAT or
a Transit Gateway).

Features:

- Single `endpoints` map drives both Interface and Gateway endpoints via one
  `aws_vpc_endpoint` resource block; the AWS service name is resolved via
  `aws_vpc_endpoint_service`, so a typo fails the plan instead of silently
  creating nothing.
- `type` ("Gateway" or "Interface") is a required field, not inferred. AWS
  exposes some services (S3, DynamoDB) as two distinct `ServiceDetail`
  records under the identical service name, differing only in
  `ServiceType` — confirmed against a live account
  (`describe-vpc-endpoint-services --filters Name=service-name,...s3`
  returns one `Gateway` and one `Interface` record). Without `service_type`,
  `aws_vpc_endpoint_service` fails with "multiple ... matched", so there is
  nothing for the module to safely default or guess.
- Optional organization-scoped baseline endpoint policy
  (`aws:PrincipalOrgID`), opt-in via `organization_id`; a per-endpoint
  `policy_json` always overrides it.

## What does NOT belong here

- Security groups — the module attaches whatever `security_group_ids` an
  Interface endpoint entry supplies; it never creates or manages one. Same
  convention as every other shared module here (e.g. `rds-postgresql`'s
  `security_group_id`).
- Route table ownership — the module only associates Gateway endpoints with
  route table IDs supplied by the caller (typically `workload-vpc-routes`); it
  never creates or modifies route tables itself.
- Availability Zone / subnet selection for interface endpoints — the caller
  passes `subnet_ids` and is responsible for picking subnets whose AZ the
  service actually supports; AWS rejects the create call otherwise (see
  references below for the troubleshooting guide).
- DNS records for `private_dns_enabled = false` endpoints — the caller wires
  its own Route 53 records from `interface_dns_entries` if needed.
- Endpoint services (`aws_vpc_endpoint_service`, the *provider* side of
  PrivateLink) — this module is a consumer only.

## The `endpoints` map

Each key doubles as the AWS service short name (e.g. `"s3"`, `"ec2"`,
`"ecr.api"`) unless `service` or `service_name` overrides it, and as the
resource's `Name` tag unless `name` overrides it.

A Gateway endpoint:

```hcl
endpoints = {
  "s3" = { type = "Gateway", route_table_ids = local.route_table_ids }
}
```

An Interface endpoint, with a security group the caller manages:

```hcl
endpoints = {
  "sts" = {
    type                = "Interface"
    subnet_ids          = local.app_subnet_ids
    security_group_ids  = [aws_security_group.vpce.id]
  }
}
```

| Field | Notes |
|---|---|
| `name` | Overrides the key for the `Name` tag and error messages. Useful for a second entry of the same service (e.g. an Interface variant of S3 alongside the default Gateway one). |
| `type` | `"Gateway"` or `"Interface"`. Required — AWS exposes some services (S3, DynamoDB) as distinct records under the same service name, differing only by type; `aws_vpc_endpoint_service` fails the plan with "multiple ... matched" if this is ambiguous, so the module never guesses it. |
| `service` | AWS service short name passed to the data source's `service` argument (e.g. `"ec2"`, `"ecr.api"`, `"elasticloadbalancing"`). Defaults to the map key. Mutually exclusive with `service_name`. |
| `service_name` | Full service name escape hatch for non-standard or third-party services (e.g. a PrivateLink service: `"com.amazonaws.vpce.eu-central-2.vpce-svc-0123456789abcdef0"`). Mutually exclusive with `service`. |
| `subnet_ids` | Subnet IDs for the Interface endpoint's network interfaces. Required for `type = "Interface"`, must be empty for `"Gateway"`. The caller picks subnets in Availability Zones the service actually supports — AWS rejects the create call otherwise (see references below). |
| `route_table_ids` | Route table IDs the Gateway endpoint associates with. Must be empty for `"Interface"`. Leave empty (for a Gateway entry) to create the endpoint with no association yet; associations can be added on a later apply. |
| `security_group_ids` | Security group IDs to attach to an Interface endpoint. Must be empty for `"Gateway"`. The module never creates security groups — the caller manages them, same as every other shared module in this framework. |
| `private_dns_enabled` | Associate the AWS-managed private hosted zone so in-VPC callers resolve the service's public DNS name to the endpoint. Ignored for Gateway endpoints. Default `true`. |
| `policy_json` | Endpoint policy JSON. Overrides the organization-scoped baseline derived from `organization_id`, if any. Null means the AWS default (unrestricted access) unless `organization_id` supplies a baseline and the service supports endpoint policies. |

`type` also constrains which of `subnet_ids` / `route_table_ids` /
`security_group_ids` may be set — an `Interface` entry with
`route_table_ids`, or a `Gateway` entry with `subnet_ids` or
`security_group_ids`, fails validation at plan time.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_vpc_endpoint.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint_service.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc_endpoint_service) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_endpoints"></a> [endpoints](#input\_endpoints) | Map of endpoint key to its configuration. The key doubles as the AWS service short name and the resource's Name tag unless overridden. See the module README for the field reference and examples. | <pre>map(object({<br/>    name                = optional(string)<br/>    type                = string<br/>    service             = optional(string)<br/>    service_name        = optional(string)<br/>    subnet_ids          = optional(list(string), [])<br/>    route_table_ids     = optional(list(string), [])<br/>    security_group_ids  = optional(list(string), [])<br/>    private_dns_enabled = optional(bool, true)<br/>    policy_json         = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | AWS Organizations ID (e.g. "o-xxxxxxxxxx"). When set, every endpoint whose service supports endpoint policies gets a baseline policy denying access to principals outside this organization, unless the endpoint sets its own policy\_json. Opt-in: leave null to keep the AWS default (unrestricted) policy. | `string` | `null` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to create endpoints in. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_endpoint_ids"></a> [endpoint\_ids](#output\_endpoint\_ids) | Map of endpoint key to its VPC endpoint ID (Interface and Gateway). |
| <a name="output_gateway_prefix_list_ids"></a> [gateway\_prefix\_list\_ids](#output\_gateway\_prefix\_list\_ids) | Map of Gateway endpoint key to its prefix list ID. Consumed by downstream projects that need to reference the service's CIDR range in a security group rule instead of 0.0.0.0/0. Interface endpoint keys are omitted. |
| <a name="output_interface_dns_entries"></a> [interface\_dns\_entries](#output\_interface\_dns\_entries) | Map of Interface endpoint key to its list of {dns\_name, hosted\_zone\_id} objects. Useful when private\_dns\_enabled is false and a caller must wire its own Route 53 record. Gateway endpoint keys are omitted. |
| <a name="output_interface_network_interface_ids"></a> [interface\_network\_interface\_ids](#output\_interface\_network\_interface\_ids) | Map of Interface endpoint key to its list of network interface IDs, one per Availability Zone. Gateway endpoint keys are omitted. |
<!-- END_TF_DOCS -->

## References

- [Terraform — `aws_vpc_endpoint`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint)
- [Terraform — `aws_vpc_endpoint_service` data source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc_endpoint_service)
- [AWS — How do I configure security groups and network ACLs for a VPC interface endpoint?](https://repost.aws/knowledge-center/security-network-acl-vpc-endpoint)
- [AWS — Interface endpoint Availability Zone mismatch troubleshooting](https://repost.aws/knowledge-center/interface-endpoint-availability-zone)
- [AWS — `aws:PrincipalOrgID` global condition key](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html)
