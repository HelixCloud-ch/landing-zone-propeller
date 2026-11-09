# dns-record

Publishes one DNS record into an existing Route 53 hosted zone. The module
does not create or look up the zone: the caller passes `zone_id`, so the
same module serves public and private zones.

Use a CNAME for targets that Route 53 cannot alias (RDS, ElastiCache
endpoints) and an `A`/`AAAA` alias for load balancers, CloudFront or other
alias-capable targets. Alias records have a fixed 60-second TTL, so `ttl` is
ignored when `alias` is set.

## Cross-account zones

The module uses the default `aws` provider. When the zone lives in another
account, the caller configures an aliased provider that assumes a role in
the zone's account and passes it in:

```hcl
provider "aws" {
  alias  = "dns"
  region = var.region
  assume_role {
    role_arn = var.dns_publisher_role_arn
  }
}

module "dns_record" {
  source    = "../../../shared/modules/dns-record"
  providers = { aws = aws.dns }

  zone_id = var.dns_zone_id
  name    = "redis"
  records = [module.redis.primary_endpoint]
}
```

Hosted zones have no resource-based policy, so cross-account writes always
go through a role in the zone's account. Scope that role with the Route 53
record-name and record-type condition keys.

## References

- [Choosing between alias and non-alias records](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html)
- [Routing traffic to an ELB load balancer](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-elb-load-balancer.html)
- [Using IAM policy conditions for fine-grained access control](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/specifying-conditions-route53.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.41 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.70.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alias"></a> [alias](#input\_alias) | Alias target (e.g. a load balancer's dns\_name and zone\_id). Mutually exclusive with records. | <pre>object({<br/>    name                   = string<br/>    zone_id                = string<br/>    evaluate_target_health = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Record name, relative to the zone (e.g. 'redis') or fully qualified. | `string` | n/a | yes |
| <a name="input_records"></a> [records](#input\_records) | Record values for a non-alias record. A CNAME takes exactly one value. | `list(string)` | `[]` | no |
| <a name="input_ttl"></a> [ttl](#input\_ttl) | TTL in seconds for non-alias records. Ignored for alias records (fixed at 60). | `number` | `300` | no |
| <a name="input_type"></a> [type](#input\_type) | Record type: A, AAAA, CNAME or TXT. Alias records require A or AAAA. | `string` | `"CNAME"` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | ID of the Route 53 hosted zone that receives the record. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | Fully qualified name of the record, without the trailing dot. |
<!-- END_TF_DOCS -->
