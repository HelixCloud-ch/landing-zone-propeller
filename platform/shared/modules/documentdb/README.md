# documentdb

Shared Terraform module for Amazon DocumentDB clusters. Used by the
`documentdb` platform project.

Features:

- Cluster with configurable instance count (1 writer + N-1 readers)
- Secrets Manager-managed master password (or write-only password mode)
- Encryption at rest (KMS) and in transit (TLS enabled by default)
- Snapshot restore support for lifecycle management
- BYO security group or module-managed with CIDR and SG-reference ingress rules
- CloudWatch log exports (audit, profiler)
- I/O-optimized storage type option (iopt1)
- Comprehensive input validation

## Architecture difference vs. RDS modules

DocumentDB is a cluster-based service (similar to Aurora). Instead of a single
`aws_db_instance`, this module creates:

1. `aws_docdb_cluster` — the cluster (storage layer, endpoints, credentials)
2. `aws_docdb_cluster_instance` × N — compute instances (writer + readers)
3. `aws_docdb_subnet_group` — subnet placement

There is no `db_name` concept — databases are created at the application level
using the MongoDB wire protocol.

## DocumentDB-specific constraints

| Parameter | Constraint |
|-----------|-----------|
| `cluster_identifier` | 1-63 chars, lowercase, starts with letter, alphanumerics/hyphens, no consecutive/trailing hyphens |
| `master_username` | 1-63 chars, starts with a letter, letters and digits only |
| `master_password` | 8-100 chars, printable ASCII excluding `/`, `"`, `@` |
| `log exports` | `audit`, `profiler` |
| `default port` | 27017 |
| `storage_type` | `standard`, `iopt1` |

## What does NOT belong here

- Application-level users/collections — manage via application code or migration tool
- DocumentDB Elastic Clusters — separate module (different resource types)
- Global clusters — future extension
- VPC peering or PrivateLink — handled by networking projects

## References

- [DocumentDB naming constraints and quotas](https://docs.aws.amazon.com/documentdb/latest/devguide/limits.html)
- [Security best practices for DocumentDB](https://docs.aws.amazon.com/documentdb/latest/devguide/security_best_practices.html)
- [aws_docdb_cluster Terraform resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/docdb_cluster)
- [aws_docdb_cluster_instance Terraform resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/docdb_cluster_instance)

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
| [aws_docdb_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/docdb_cluster) | resource |
| [aws_docdb_cluster_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/docdb_cluster_instance) | resource |
| [aws_docdb_cluster_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/docdb_cluster_parameter_group) | resource |
| [aws_docdb_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/docdb_subnet_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.ingress_cidrs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ingress_sgs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_docdb_engine_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/docdb_engine_version) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allow_major_version_upgrade"></a> [allow\_major\_version\_upgrade](#input\_allow\_major\_version\_upgrade) | Allow major engine version upgrades when changing engine\_version. | `bool` | `true` | no |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | CIDR blocks allowed to connect to the cluster. | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | Security group IDs allowed to connect to the cluster. | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply changes immediately instead of during the next maintenance window. | `bool` | `false` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Days to retain automated backups (1 to 35). | `number` | `7` | no |
| <a name="input_cluster_identifier"></a> [cluster\_identifier](#input\_cluster\_identifier) | Unique identifier for the DocumentDB cluster. Used for naming all associated resources. | `string` | n/a | yes |
| <a name="input_cluster_parameters"></a> [cluster\_parameters](#input\_cluster\_parameters) | Map of DocumentDB cluster parameter group parameters. The parameter group is created automatically with the correct family derived from engine\_version. | `map(string)` | `{}` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Prevent accidental deletion of the cluster. | `bool` | `true` | no |
| <a name="input_enable_performance_insights"></a> [enable\_performance\_insights](#input\_enable\_performance\_insights) | Enable Performance Insights on cluster instances. | `bool` | `false` | no |
| <a name="input_enabled_cloudwatch_logs_exports"></a> [enabled\_cloudwatch\_logs\_exports](#input\_enabled\_cloudwatch\_logs\_exports) | List of log types to export to CloudWatch. Valid values for DocumentDB: 'audit', 'profiler'. | `list(string)` | <pre>[<br/>  "audit"<br/>]</pre> | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | DocumentDB engine version (e.g. '8.0.0', '5.0.0'). Validated at plan time against available versions in the target region. | `string` | `"8.0.0"` | no |
| <a name="input_final_snapshot_identifier"></a> [final\_snapshot\_identifier](#input\_final\_snapshot\_identifier) | Name for the final snapshot on deletion. If empty, defaults to '{cluster\_identifier}-final'. | `string` | `""` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | Instance class for cluster instances (e.g. 'db.r6g.large', 'db.t3.medium'). | `string` | `"db.t3.medium"` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of cluster instances (1 writer + N-1 readers). Minimum 1. | `number` | `1` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | KMS key ARN for storage encryption. Uses default aws/docdb key if not specified. | `string` | `null` | no |
| <a name="input_master_password"></a> [master\_password](#input\_master\_password) | Master password. Used only when master\_user\_secret\_kms\_key\_id is not set. Ephemeral: never written to state (delivered via write-only argument). 8-100 printable ASCII chars excluding '/', '"', '@'. | `string` | `null` | no |
| <a name="input_master_password_wo_version"></a> [master\_password\_wo\_version](#input\_master\_password\_wo\_version) | Bump to rotate the write-only password. Only relevant in password mode. | `number` | `1` | no |
| <a name="input_master_user_secret_kms_key_id"></a> [master\_user\_secret\_kms\_key\_id](#input\_master\_user\_secret\_kms\_key\_id) | KMS key ARN for Secrets Manager-managed master password. When set, credentials are managed by Secrets Manager. | `string` | `null` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Master username for the cluster. 1-63 alphanumeric chars, starts with a letter. | `string` | `"docdbadmin"` | no |
| <a name="input_port"></a> [port](#input\_port) | Port the DocumentDB cluster listens on. | `number` | `27017` | no |
| <a name="input_preferred_backup_window"></a> [preferred\_backup\_window](#input\_preferred\_backup\_window) | Daily time range for automated backups (UTC). Format: hh:mm-hh:mm. | `string` | `"03:00-04:00"` | no |
| <a name="input_preferred_maintenance_window"></a> [preferred\_maintenance\_window](#input\_preferred\_maintenance\_window) | Weekly maintenance window (UTC). Format: ddd:hh:mm-ddd:hh:mm. | `string` | `"sun:05:00-sun:06:00"` | no |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | Existing security group ID to use instead of creating one. When set, the module skips SG creation and all ingress rule management. Mutually exclusive with allowed\_cidrs and allowed\_security\_group\_ids. | `string` | `null` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Skip final snapshot on deletion. Keep false so a snapshot is taken before destroy. | `bool` | `false` | no |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | Cluster snapshot to restore from on create. Empty string means create fresh. | `string` | `""` | no |
| <a name="input_storage_encrypted"></a> [storage\_encrypted](#input\_storage\_encrypted) | Whether to encrypt cluster storage at rest. Enabled by default (cannot be changed after creation). | `bool` | `true` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage\_type) | Storage type for the cluster: 'standard' or 'iopt1' (I/O-optimized). | `string` | `"standard"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for the DB subnet group. At least 2 subnets in different AZs are required. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the security group will be created. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the DocumentDB cluster. |
| <a name="output_cluster_identifier"></a> [cluster\_identifier](#output\_cluster\_identifier) | DocumentDB cluster identifier. |
| <a name="output_cluster_members"></a> [cluster\_members](#output\_cluster\_members) | List of instance identifiers that are part of the cluster. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Primary (writer) endpoint for the DocumentDB cluster. |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | ARN of the Secrets Manager secret containing the master user credentials. |
| <a name="output_master_username"></a> [master\_username](#output\_master\_username) | The master username for the cluster. |
| <a name="output_port"></a> [port](#output\_port) | Cluster port. |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | Reader endpoint, automatically load-balanced across replicas. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the security group used by the cluster (created or caller-provided). |
<!-- END_TF_DOCS -->
