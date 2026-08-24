# Aurora PostgreSQL

Deploys an Aurora PostgreSQL Serverless v2 cluster with managed credentials via
Secrets Manager, encrypted storage, configurable networking, and sleep/wake
support (scale-to-zero auto-pause or snapshot modes).

## What it deploys

- **DB subnet group** from the selected tier subnets
- **Security group** with configurable ingress (CIDRs or SG references)
- **Aurora PostgreSQL cluster** (Serverless v2, scale-to-zero capable)
- **Serverless v2 instances** (1 writer + optional readers)
- **Master credentials** auto-managed in Secrets Manager (no plaintext password)

## Pipeline wiring

```yaml
stages:
  - name: database
    steps:
      - project: aurora-postgresql
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
identifier     = "my-aurora-db"
engine_version = "17"

# Access — at least one must be set for connectivity
allowed_cidrs = ["10.0.0.0/8"]

# Scale-to-zero (default): cluster pauses after 5 min idle
min_capacity             = 0
max_capacity             = 4
seconds_until_auto_pause = 300

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
| `pause` (default) | No-op (auto-pause on idle) | No-op (auto-resume on connect) | Yes |
| `snapshot` | Destroy cluster with final snapshot | Restore from snapshot, delete snapshot | Yes |
| `destroy` | Full `terraform destroy` | Full `terraform apply` | No |

The `pause` mode relies on Aurora Serverless v2's native scale-to-zero
(`min_capacity = 0`). The cluster pauses automatically after
`seconds_until_auto_pause` of inactivity and resumes on the next connection
(~25s cold start).

## Engine versions

To list available Aurora PostgreSQL versions:

```bash
aws rds describe-db-engine-versions \
  --engine aurora-postgresql \
  --query 'DBEngineVersions[].EngineVersion' \
  --output table
```

## What does NOT belong here

- Application-level users/schemas — use a separate migration project or tool
- Global databases (multi-region) — separate project
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
| <a name="module_aurora_postgresql"></a> [aurora\_postgresql](#module\_aurora\_postgresql) | ../../../shared/modules/aurora-postgresql | n/a |
| <a name="module_credential"></a> [credential](#module\_credential) | ../../../shared/modules/ephemeral-credential | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
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
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Aurora PostgreSQL major version (e.g. '17'). | `string` | `"17"` | no |
| <a name="input_final_snapshot_identifier"></a> [final\_snapshot\_identifier](#input\_final\_snapshot\_identifier) | n/a | `string` | `""` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Unique identifier for the Aurora cluster. | `string` | n/a | yes |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of Serverless v2 instances (1 writer + N-1 readers). | `number` | `1` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | n/a | `string` | `null` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | n/a | `string` | `"sun:05:00-sun:06:00"` | no |
| <a name="input_max_capacity"></a> [max\_capacity](#input\_max\_capacity) | Maximum ACU. | `number` | `4` | no |
| <a name="input_min_capacity"></a> [min\_capacity](#input\_min\_capacity) | Minimum ACU. Set to 0 for scale-to-zero auto-pause. | `number` | `0` | no |
| <a name="input_performance_insights_enabled"></a> [performance\_insights\_enabled](#input\_performance\_insights\_enabled) | n/a | `bool` | `false` | no |
| <a name="input_port"></a> [port](#input\_port) | n/a | `number` | `5432` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | n/a | yes |
| <a name="input_seconds_until_auto_pause"></a> [seconds\_until\_auto\_pause](#input\_seconds\_until\_auto\_pause) | Idle seconds before auto-pause (when min\_capacity=0). Range 300-86400. | `number` | `300` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | n/a | `bool` | `false` | no |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | n/a | `string` | `""` | no |
| <a name="input_storage_encrypted"></a> [storage\_encrypted](#input\_storage\_encrypted) | n/a | `bool` | `true` | no |
| <a name="input_subnet_ids_json"></a> [subnet\_ids\_json](#input\_subnet\_ids\_json) | JSON string of subnet tier map (from VPC project output). Decoded to extract the selected tier. | `string` | n/a | yes |
| <a name="input_subnet_tier"></a> [subnet\_tier](#input\_subnet\_tier) | Key in the subnet map to use for the DB subnet group. | `string` | `"data"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_username"></a> [username](#input\_username) | n/a | `string` | `"dbadmin"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID (from VPC project output). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_identifier"></a> [cluster\_identifier](#output\_cluster\_identifier) | Aurora cluster identifier (used by sleep/wake justfile recipes). |
| <a name="output_credential_secret_arn"></a> [credential\_secret\_arn](#output\_credential\_secret\_arn) | ARN of the Secrets Manager secret created by ephemeral-credential (secret\_name mode only). |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Writer endpoint (hostname) of the Aurora cluster. |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | ARN of the RDS-managed Secrets Manager secret (manage\_master\_user\_password mode only). |
| <a name="output_port"></a> [port](#output\_port) | Database port. |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | Reader endpoint (hostname) of the Aurora cluster. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID for the Aurora cluster. |
<!-- END_TF_DOCS -->
