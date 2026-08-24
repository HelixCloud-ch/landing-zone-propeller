# DocumentDB

Deploys an Amazon DocumentDB cluster with managed credentials via Secrets Manager,
encryption at rest and in transit, configurable networking, and sleep/wake support.

## What it deploys

- **DocDB subnet group** from the selected tier subnets
- **Security group** with configurable ingress (CIDRs or SG references)
- **DocumentDB cluster** with configurable storage type (standard or iopt1)
- **Cluster instances** (1 writer + N-1 readers)
- **Master credentials** auto-managed in Secrets Manager (no plaintext password)

## Pipeline wiring

```yaml
stages:
  - name: database
    steps:
      - project: documentdb
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

Only `region`, `cluster_identifier`, and `engine_version` are required.
Everything else has sensible defaults:

```hcl
region             = "eu-central-2"
cluster_identifier = "my-docdb"
engine_version     = "5.0.0"

# Access — at least one must be set for connectivity
allowed_cidrs = ["10.0.0.0/8"]

# Scale out with readers:
# instance_count = 3

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

Returns `{"username": "docdbadmin", "password": "..."}`.

## Connecting

DocumentDB requires TLS by default. Download the CA bundle and connect:

```bash
wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
mongosh --tls --tlsCAFile global-bundle.pem \
  --host <endpoint> --port 27017 \
  --username docdbadmin --password <password>
```

## Sleep/Wake modes

| Mode | Sleep | Wake | Data preserved |
|------|-------|------|----------------|
| `stop` (default) | `aws docdb stop-db-cluster` | `aws docdb start-db-cluster` + wait | Yes (7-day auto-restart limit) |
| `snapshot` | Targeted destroy with final snapshot | Restore from snapshot, delete snapshot | Yes |
| `destroy` | Full `terraform destroy` | Full `terraform apply` | No |

## Engine versions

To list available versions:

```bash
aws docdb describe-db-engine-versions \
  --engine docdb \
  --query 'DBEngineVersions[].EngineVersion' \
  --output table
```

## What does NOT belong here

- Application-level users/collections — manage via application code
- DocumentDB Elastic Clusters — use a separate elastic-cluster module
- Global clusters — future extension
- Read preference/connection string tuning — application-level concern

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
| <a name="module_documentdb"></a> [documentdb](#module\_documentdb) | ../../../shared/modules/documentdb | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allow_major_version_upgrade"></a> [allow\_major\_version\_upgrade](#input\_allow\_major\_version\_upgrade) | n/a | `bool` | `true` | no |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | n/a | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | n/a | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | n/a | `bool` | `false` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | n/a | `number` | `7` | no |
| <a name="input_cluster_identifier"></a> [cluster\_identifier](#input\_cluster\_identifier) | Unique identifier for the DocumentDB cluster. | `string` | n/a | yes |
| <a name="input_cluster_parameters"></a> [cluster\_parameters](#input\_cluster\_parameters) | DocumentDB cluster parameter group parameters (e.g. {tls = "enabled"}). | `map(string)` | `{}` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_credential"></a> [credential](#input\_credential) | Credential strategy. Set one of secret\_name/secret\_arn/parameter\_name/<br/>parameter\_arn to use the ephemeral-credential module. Leave all null to<br/>use DocDB-managed master password (manage\_master\_user\_password=true with<br/>kms\_key\_id for encryption). | <pre>object({<br/>    # Identity — set exactly one, or leave all null for DocDB-managed mode<br/>    secret_name    = optional(string)<br/>    secret_arn     = optional(string)<br/>    parameter_name = optional(string)<br/>    parameter_arn  = optional(string)<br/><br/>    # Password generation<br/>    password = optional(object({<br/>      length                     = optional(number, 28)<br/>      exclude_characters         = optional(string, "/@\"\\\n")<br/>      exclude_lowercase          = optional(bool, false)<br/>      exclude_numbers            = optional(bool, false)<br/>      exclude_punctuation        = optional(bool, false)<br/>      exclude_uppercase          = optional(bool, false)<br/>      include_space              = optional(bool, false)<br/>      require_each_included_type = optional(bool, true)<br/>    }), {})<br/><br/>    # Rotation & encryption<br/>    password_version = optional(number, 1)<br/>    kms_key_id       = optional(string)<br/>    description      = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | n/a | `bool` | `true` | no |
| <a name="input_enable_performance_insights"></a> [enable\_performance\_insights](#input\_enable\_performance\_insights) | n/a | `bool` | `true` | no |
| <a name="input_enabled_cloudwatch_logs_exports"></a> [enabled\_cloudwatch\_logs\_exports](#input\_enabled\_cloudwatch\_logs\_exports) | n/a | `list(string)` | <pre>[<br/>  "audit"<br/>]</pre> | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | DocumentDB engine version (e.g. '8.0.0'). | `string` | `"8.0.0"` | no |
| <a name="input_final_snapshot_identifier"></a> [final\_snapshot\_identifier](#input\_final\_snapshot\_identifier) | n/a | `string` | `""` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | Instance class for cluster instances. | `string` | `"db.t3.medium"` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of cluster instances (1 writer + N-1 readers). | `number` | `1` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | n/a | `string` | `null` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | n/a | `string` | `"docdbadmin"` | no |
| <a name="input_port"></a> [port](#input\_port) | n/a | `number` | `27017` | no |
| <a name="input_preferred_backup_window"></a> [preferred\_backup\_window](#input\_preferred\_backup\_window) | n/a | `string` | `"03:00-04:00"` | no |
| <a name="input_preferred_maintenance_window"></a> [preferred\_maintenance\_window](#input\_preferred\_maintenance\_window) | n/a | `string` | `"sun:05:00-sun:06:00"` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | n/a | yes |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | n/a | `bool` | `false` | no |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | n/a | `string` | `""` | no |
| <a name="input_storage_encrypted"></a> [storage\_encrypted](#input\_storage\_encrypted) | n/a | `bool` | `true` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage\_type) | n/a | `string` | `"standard"` | no |
| <a name="input_subnet_ids_json"></a> [subnet\_ids\_json](#input\_subnet\_ids\_json) | JSON string of subnet tier map (from VPC project output). Decoded to extract the selected tier. | `string` | n/a | yes |
| <a name="input_subnet_tier"></a> [subnet\_tier](#input\_subnet\_tier) | Key in the subnet map to use for the DB subnet group. | `string` | `"data"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID (from VPC project output). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_identifier"></a> [cluster\_identifier](#output\_cluster\_identifier) | DocumentDB cluster identifier (used by sleep/wake justfile recipes). |
| <a name="output_credential_secret_arn"></a> [credential\_secret\_arn](#output\_credential\_secret\_arn) | ARN of the Secrets Manager secret created by ephemeral-credential (secret\_name mode only). |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Primary (writer) endpoint for the DocumentDB cluster. |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | ARN of the DocDB-managed Secrets Manager secret (manage\_master\_user\_password mode only). |
| <a name="output_port"></a> [port](#output\_port) | Cluster port. |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | Reader endpoint, load-balanced across replicas. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID for the DocumentDB cluster. |
<!-- END_TF_DOCS -->
