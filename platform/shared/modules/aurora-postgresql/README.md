# aurora-postgresql

Shared Terraform module for Aurora PostgreSQL Serverless v2 clusters. Used by
the `aurora-postgresql` platform project.

Features:

- Aurora Serverless v2 with scale-to-zero auto-pause (min_capacity = 0)
- Secrets Manager-managed master password (or write-only password mode)
- BYO security group or module-managed with CIDR, SG-reference, and custom egress rules
- Plan-time validation of engine version + Serverless v2 orderability
- Snapshot restore support for lifecycle management
- Comprehensive input validation (formats, ranges, cross-variable constraints)

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
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_rds_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.custom](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ingress_cidrs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ingress_sgs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_rds_engine_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/rds_engine_version) | data source |
| [aws_rds_orderable_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/rds_orderable_db_instance) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | CIDR blocks allowed to connect to the database. | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | Security group IDs allowed to connect to the database. | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply changes immediately instead of during the next maintenance window. | `bool` | `false` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | Apply minor version upgrades automatically during the maintenance window. | `bool` | `true` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Days to retain automated backups (1-35). Aurora does not allow 0. | `number` | `7` | no |
| <a name="input_backup_window"></a> [backup\_window](#input\_backup\_window) | Daily time range for automated backups (UTC). Format: hh:mm-hh:mm. | `string` | `"03:00-04:00"` | no |
| <a name="input_create_egress_rule"></a> [create\_egress\_rule](#input\_create\_egress\_rule) | Create an allow-all egress rule on the security group. Keep true for the common case; set false to restrict egress (via egress\_rules) or manage it externally. | `bool` | `true` | no |
| <a name="input_db_cluster_parameter_group_name"></a> [db\_cluster\_parameter\_group\_name](#input\_db\_cluster\_parameter\_group\_name) | DB cluster parameter group name. Uses engine default if not specified. | `string` | `null` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Name of the initial database to create. | `string` | `"appdb"` | no |
| <a name="input_db_parameter_group_name"></a> [db\_parameter\_group\_name](#input\_db\_parameter\_group\_name) | DB instance parameter group name. Uses engine default if not specified. | `string` | `null` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Prevent accidental deletion of the cluster. | `bool` | `true` | no |
| <a name="input_egress_rules"></a> [egress\_rules](#input\_egress\_rules) | Explicit egress rules for restricted setups. Used with create\_egress\_rule = false. | <pre>list(object({<br/>    cidr_ipv4   = string<br/>    from_port   = number<br/>    to_port     = number<br/>    ip_protocol = optional(string, "tcp")<br/>    description = optional(string, "")<br/>  }))</pre> | `[]` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Aurora PostgreSQL major version (e.g. '17'). Auto-pause (min\_capacity = 0) requires a recent version. | `string` | `"17"` | no |
| <a name="input_final_snapshot_identifier"></a> [final\_snapshot\_identifier](#input\_final\_snapshot\_identifier) | Name for the final snapshot on deletion. Defaults to '{identifier}-final'. | `string` | `""` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Unique identifier for the Aurora cluster. Used for naming all associated resources. | `string` | n/a | yes |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of Serverless v2 instances (1 writer + N-1 readers). | `number` | `1` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | KMS key ARN for storage encryption. Uses default aws/rds key if not specified. | `string` | `null` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Weekly maintenance window (UTC). Format: ddd:hh:mm-ddd:hh:mm. | `string` | `"sun:05:00-sun:06:00"` | no |
| <a name="input_master_user_secret_kms_key_id"></a> [master\_user\_secret\_kms\_key\_id](#input\_master\_user\_secret\_kms\_key\_id) | KMS key for Secrets Manager-managed master password. When set, 'password' must not be provided. | `string` | `null` | no |
| <a name="input_max_capacity"></a> [max\_capacity](#input\_max\_capacity) | Maximum Aurora Capacity Units (ACU). | `number` | `4` | no |
| <a name="input_min_capacity"></a> [min\_capacity](#input\_min\_capacity) | Minimum Aurora Capacity Units (ACU). Set to 0 for scale-to-zero auto-pause. | `number` | `0` | no |
| <a name="input_password"></a> [password](#input\_password) | Master password (write-only, never in state). Mutually exclusive with master\_user\_secret\_kms\_key\_id. | `string` | `null` | no |
| <a name="input_password_wo_version"></a> [password\_wo\_version](#input\_password\_wo\_version) | Bump to rotate the write-only password. Only relevant in password mode. | `number` | `1` | no |
| <a name="input_performance_insights_enabled"></a> [performance\_insights\_enabled](#input\_performance\_insights\_enabled) | Enable Performance Insights. Keep disabled with scale-to-zero (forces non-zero min ACU). | `bool` | `false` | no |
| <a name="input_port"></a> [port](#input\_port) | Port the PostgreSQL server listens on. | `number` | `5432` | no |
| <a name="input_seconds_until_auto_pause"></a> [seconds\_until\_auto\_pause](#input\_seconds\_until\_auto\_pause) | Idle seconds before auto-pause when min\_capacity is 0. Range 300-86400. | `number` | `300` | no |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | Existing security group to attach the cluster to. When set, the module does not create its own security group; ingress/egress rules are skipped — manage rules on the external group. Mutually exclusive with allowed\_cidrs and allowed\_security\_group\_ids. | `string` | `null` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Skip final snapshot on deletion. | `bool` | `false` | no |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | Cluster snapshot to restore from on create. Empty = create fresh. | `string` | `""` | no |
| <a name="input_storage_encrypted"></a> [storage\_encrypted](#input\_storage\_encrypted) | Whether to encrypt storage at rest. | `bool` | `true` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for the DB subnet group (data tier). At least 2 subnets in different AZs are required. | `list(string)` | n/a | yes |
| <a name="input_username"></a> [username](#input\_username) | Master username for the database. | `string` | `"dbadmin"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the security group will be created. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the Aurora cluster. |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | Aurora cluster identifier. |
| <a name="output_db_name"></a> [db\_name](#output\_db\_name) | The database name. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Writer endpoint (hostname) of the Aurora cluster. |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | ARN of the Secrets Manager secret containing the master user credentials. |
| <a name="output_port"></a> [port](#output\_port) | Database port. |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | Reader endpoint (hostname) of the Aurora cluster. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the security group used by the Aurora cluster (the created one, or the caller-provided security\_group\_id). |
| <a name="output_username"></a> [username](#output\_username) | The master username for the database. |
<!-- END_TF_DOCS -->
