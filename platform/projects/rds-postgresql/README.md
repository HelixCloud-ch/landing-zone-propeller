# RDS PostgreSQL

Deploys an RDS PostgreSQL instance with managed credentials via Secrets Manager,
encrypted storage, configurable networking, and sleep/wake support.

## What it deploys

- **DB subnet group** from the selected tier subnets
- **Security group** with configurable ingress (CIDRs or SG references)
- **RDS PostgreSQL instance** with storage autoscaling
- **Master credentials** auto-managed in Secrets Manager (no plaintext password)

## Pipeline wiring

```yaml
stages:
  - name: database
    steps:
      - project: rds-postgresql
        target: workload-account
        depends_on: [vpc]
        inputs:
          - name: vpc.vpc_id
            var: vpc_id
          - name: vpc.subnet_ids_by_tier
            var: subnet_ids_json
```

The `subnet_ids_json` input is the JSON-encoded map from the VPC project. The
project decodes it and extracts the `data` tier by default (configurable via
`subnet_tier`).

## Consumer tfvars

Only `region`, `identifier`, and `engine_version` are required. Everything else
has sensible defaults:

```hcl
region         = "eu-central-2"
identifier     = "my-postgres-db"
engine_version = "16"

# Access — at least one must be set for connectivity
allowed_cidrs = ["10.0.0.0/8"]

# For testing (allows fast teardown):
# deletion_protection = false
# skip_final_snapshot = true
```

## Retrieving credentials

```bash
aws secretsmanager get-secret-value \
  --secret-id <master_user_secret_arn> \
  --query SecretString --output text | jq .
```

Returns `{"username": "dbadmin", "password": "..."}`.

## Sleep/Wake modes

| Mode | Sleep | Wake | Data preserved |
|------|-------|------|----------------|
| `stop` (default) | `aws rds stop-db-instance` | `aws rds start-db-instance` + wait | Yes (7-day auto-restart limit) |
| `snapshot` | Targeted destroy with final snapshot | Restore from snapshot, delete snapshot | Yes |
| `destroy` | Full `terraform destroy` | Full `terraform apply` | No |

## Engine versions

To list available versions:

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --query 'DBEngineVersions[].EngineVersion' \
  --output table
```

Setting `engine_version` to the major number (e.g. `"16"`) lets RDS auto-select
the latest minor. Pin a specific minor for production stability if needed.

## What does NOT belong here

- Application-level users/schemas — use a separate migration project or tool
- Read replicas — future extension of the shared module
- RDS Proxy — separate project (cross-account connectivity pattern)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_credential"></a> [credential](#module\_credential) | ../../../shared/modules/ephemeral-credential | n/a |
| <a name="module_rds_postgresql"></a> [rds\_postgresql](#module\_rds\_postgresql) | ../../../shared/modules/rds-postgresql | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allocated_storage"></a> [allocated\_storage](#input\_allocated\_storage) | n/a | `number` | `20` | no |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | n/a | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | n/a | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | n/a | `bool` | `false` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | n/a | `bool` | `true` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | n/a | `number` | `7` | no |
| <a name="input_backup_window"></a> [backup\_window](#input\_backup\_window) | n/a | `string` | `"03:00-04:00"` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_credential"></a> [credential](#input\_credential) | Credential strategy. Set one of secret\_name/secret\_arn/parameter\_name/<br/>parameter\_arn to use the ephemeral-credential module. Leave all null to<br/>use RDS-managed master password (manage\_master\_user\_password=true with<br/>kms\_key\_id for encryption). | <pre>object({<br/>    # Identity — set exactly one, or leave all null for RDS-managed mode<br/>    secret_name    = optional(string)<br/>    secret_arn     = optional(string)<br/>    parameter_name = optional(string)<br/>    parameter_arn  = optional(string)<br/><br/>    # Password generation<br/>    password = optional(object({<br/>      length                     = optional(number, 28)<br/>      exclude_characters         = optional(string, "/@\"\\'\n")<br/>      exclude_lowercase          = optional(bool, false)<br/>      exclude_numbers            = optional(bool, false)<br/>      exclude_punctuation        = optional(bool, false)<br/>      exclude_uppercase          = optional(bool, false)<br/>      include_space              = optional(bool, false)<br/>      require_each_included_type = optional(bool, true)<br/>    }), {})<br/><br/>    # Rotation & encryption<br/>    password_version = optional(number, 1)<br/>    kms_key_id       = optional(string)<br/>    description      = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | n/a | `string` | `"appdb"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | n/a | `bool` | `true` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | PostgreSQL major version (e.g. '16'). | `string` | `"16"` | no |
| <a name="input_final_snapshot_identifier"></a> [final\_snapshot\_identifier](#input\_final\_snapshot\_identifier) | n/a | `string` | `""` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Unique identifier for the RDS instance. | `string` | n/a | yes |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | RDS instance class. | `string` | `"db.t3.medium"` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | n/a | `string` | `null` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | n/a | `string` | `"sun:05:00-sun:06:00"` | no |
| <a name="input_max_allocated_storage"></a> [max\_allocated\_storage](#input\_max\_allocated\_storage) | n/a | `number` | `40` | no |
| <a name="input_multi_az"></a> [multi\_az](#input\_multi\_az) | n/a | `bool` | `false` | no |
| <a name="input_performance_insights_enabled"></a> [performance\_insights\_enabled](#input\_performance\_insights\_enabled) | n/a | `bool` | `true` | no |
| <a name="input_port"></a> [port](#input\_port) | n/a | `number` | `5432` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | n/a | yes |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | n/a | `bool` | `false` | no |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | n/a | `string` | `""` | no |
| <a name="input_storage_encrypted"></a> [storage\_encrypted](#input\_storage\_encrypted) | n/a | `bool` | `true` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage\_type) | n/a | `string` | `"gp3"` | no |
| <a name="input_subnet_ids_json"></a> [subnet\_ids\_json](#input\_subnet\_ids\_json) | JSON string of subnet tier map (from VPC project output). Decoded to extract the selected tier. | `string` | n/a | yes |
| <a name="input_subnet_tier"></a> [subnet\_tier](#input\_subnet\_tier) | Key in the subnet map to use for the DB subnet group. | `string` | `"data"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_username"></a> [username](#input\_username) | Master username. Ignored when credential.username is set (generated). | `string` | `"dbadmin"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID (from VPC project output). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_address"></a> [address](#output\_address) | Hostname of the RDS instance. |
| <a name="output_credential_secret_arn"></a> [credential\_secret\_arn](#output\_credential\_secret\_arn) | ARN of the Secrets Manager secret created by ephemeral-credential (secret\_name mode only). |
| <a name="output_db_instance_identifier"></a> [db\_instance\_identifier](#output\_db\_instance\_identifier) | RDS instance identifier (used by sleep/wake justfile recipes). |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Connection endpoint (address:port). |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | ARN of the RDS-managed Secrets Manager secret (manage\_master\_user\_password mode only). |
| <a name="output_port"></a> [port](#output\_port) | Database port. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID for the RDS instance. |
<!-- END_TF_DOCS -->
