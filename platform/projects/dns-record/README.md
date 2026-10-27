# dns-record

Publishes one or more DNS records into a single existing Route 53 hosted
zone. The project fans out over the [`dns-record`](../../shared/modules/dns-record)
shared module (one module instance per record); the module stays the
single-record primitive.

## Where it runs

The step's `target` is the account that owns the zone — in practice the
networking account, which holds the per-environment private zone and is
associated with the consumer VPCs. Because the records and the zone live in
the same account, the step needs no cross-account role: the deploy-runner it
already assumes in that account can write them.

A platform pipeline publishing a name for one of its own resources adds a
`dns-record` step with `target: networking`, depends on the project that
creates the resource, and wires the record value from that project's output.

## Records input

`records` is a map keyed by an arbitrary stable id (that key is the terraform
state address, not the DNS name). Each entry sets `name` and exactly one of:

- `records` — non-alias values, e.g. a CNAME to an RDS or ElastiCache
  endpoint (a CNAME takes one value);
- `alias` — an A/AAAA alias to a load balancer (`name` + `zone_id`).

The project validates the one-of rule up front; the module enforces the
per-record detail (alias only A/AAAA, CNAME single value).

### Wiring a single pipeline value into a record

Pipeline inputs resolve to scalars. A JSONata `expr` shapes a scalar into the
map entry the variable expects. For one value into one entry's `records` list:

```yaml
inputs:
  - name: rds-oracle-1.endpoint
    var: records
    expr: '{ "oracle": { "name": "oracle", "records": [$] } }'
```

The engine JSON-encodes the transformed value and the shared recipe decodes
the object into the `records` map, so `[$]` lands as a real one-element list.
Records known at author time are set in `config.auto.tfvars`; the two merge
only if wired to different variables, so prefer one source per instance.

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
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags. | `map(string)` | `{}` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags. | `map(string)` | `{}` | no |
| <a name="input_records"></a> [records](#input\_records) | Records to publish in the zone, keyed by an arbitrary stable id (the<br/>terraform state address, not the DNS name). Each entry sets `name` plus<br/>exactly one of `records` (non-alias, e.g. a CNAME to a service endpoint)<br/>or `alias` (A/AAAA to a load balancer); the module enforces that.<br/><br/>To wire a single value from the pipeline into an entry's one-element<br/>`records` list, use a JSONata input transform: `expr: '[$]'`. | <pre>map(object({<br/>    name    = string<br/>    type    = optional(string, "CNAME")<br/>    ttl     = optional(number, 300)<br/>    records = optional(list(string), [])<br/>    alias = optional(object({<br/>      name                   = string<br/>      zone_id                = string<br/>      evaluate_target_health = optional(bool, false)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags. | `map(string)` | `{}` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | ID of the Route 53 hosted zone that receives the records. The zone must exist in the deployment (target) account. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_fqdns"></a> [fqdns](#output\_fqdns) | Published record FQDNs (without trailing dot), keyed by the same ids as the records input. |
<!-- END_TF_DOCS -->
