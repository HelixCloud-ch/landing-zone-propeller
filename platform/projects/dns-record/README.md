# dns-record

Publishes a single DNS record into an existing Route 53 hosted zone. A thin
wrapper over the [`dns-record`](../../shared/modules/dns-record) shared
module.

## Where it runs

The step's `target` is the account that owns the zone — in practice the
networking account, which holds the per-environment private zone and is
associated with the consumer VPCs. Because the record and the zone live in
the same account, the step needs no cross-account role: the deploy-runner it
already assumes in that account can write the record.

A platform pipeline publishing a record for one of its own resources adds a
`dns-record` step with `target: networking`, depends on the project that
creates the resource, and wires the record value from that project's output
(e.g. an RDS or ElastiCache endpoint as a CNAME value, or a load balancer's
`dns_name`/`zone_id` as an alias target).

## Record shape

Set either `records` (non-alias, e.g. a CNAME to a service endpoint) or
`alias` (A/AAAA to a load balancer), not both — the module enforces this.
Use a CNAME for RDS and ElastiCache endpoints; use an alias for load
balancers and other alias-capable targets.

## What does NOT belong here

- The zone itself and its VPC associations. Those are created and managed
  outside propeller (for CCE, by hand, because the parent public DNS lives in
  another account).
- Record logic. The `aws_route53_record`, its alias/records validation and
  defaults live in the shared module so a non-propeller caller can reuse it.

## References

- [dns-record module](../../shared/modules/dns-record)
- [Route 53 Cross-Account Private DNS](../../../../notes/wiki/aws/route53-cross-account-dns.md)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.41 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_dns_record"></a> [dns\_record](#module\_dns\_record) | ../../../shared/modules/dns-record | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alias"></a> [alias](#input\_alias) | Alias target (e.g. a load balancer's dns\_name and zone\_id), for A/AAAA records. Set this or records, not both. | <pre>object({<br/>    name                   = string<br/>    zone_id                = string<br/>    evaluate_target_health = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags. | `map(string)` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Record name, relative to the zone (e.g. 'redis') or fully qualified. | `string` | n/a | yes |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags. | `map(string)` | `{}` | no |
| <a name="input_records"></a> [records](#input\_records) | Record values for a non-alias record (e.g. an RDS or ElastiCache endpoint). A CNAME takes one value. Set this or alias, not both. | `list(string)` | `[]` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags. | `map(string)` | `{}` | no |
| <a name="input_ttl"></a> [ttl](#input\_ttl) | TTL in seconds for non-alias records. Ignored for alias records. | `number` | `300` | no |
| <a name="input_type"></a> [type](#input\_type) | Record type: A, AAAA, CNAME or TXT. Alias records require A or AAAA. | `string` | `"CNAME"` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | ID of the Route 53 hosted zone that receives the record. The zone must exist in the deployment (target) account. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | Fully qualified name of the published record, without the trailing dot. |
<!-- END_TF_DOCS -->
