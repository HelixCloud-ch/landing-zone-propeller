# rds-postgresql

Shared Terraform module for RDS PostgreSQL instances. Used by the
`rds-postgresql` platform project.

Features:

- Storage autoscaling with configurable max
- Secrets Manager-managed master password (or write-only password mode)
- Plan-time validation of engine version + instance class + storage type
- Snapshot restore support for lifecycle management
- BYO security group or module-managed with CIDR and SG-reference ingress rules
- Comprehensive input validation (formats, ranges, cross-variable constraints)
- Optional per-instance DB parameter group (`parameters`)

## Parameter group

Set `parameters` to create a parameter group and attach it to the instance.
Set `parameter_group_name` to attach an existing group instead. The two are
mutually exclusive. With neither, the instance keeps the engine default group
and nothing changes for existing users.

```hcl
parameters = {
  "rds.logical_replication" = "1"
}
```

- The family is `postgres` plus the major version of `engine_version`
  (`"17.9"` gives `postgres17`, `"16"` and `"16.4"` give `postgres16`).
- Every parameter uses `apply_method = "pending-reboot"`. This is valid for
  static and dynamic parameters.
- A new instance gets the group at creation. On an existing instance, the
  change applies only after a manual reboot. `rds.logical_replication` is a
  static parameter. See [logical replication on RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.FeatureSupport.LogicalReplication.html).
- The module adds no parameter of its own. A custom group holds only the listed
  parameters. Other values keep the family defaults. `rds.force_ssl` is 1 by
  default on PostgreSQL 15 and later and 0 on 14 and older. See
  [SSL with RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html).
- The group name has the prefix `<identifier>-`. A family change creates the
  new group before the instance switches over.

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
| [aws_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.ingress_cidrs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ingress_sgs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_rds_engine_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/rds_engine_version) | data source |
| [aws_rds_orderable_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/rds_orderable_db_instance) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allocated_storage"></a> [allocated\_storage](#input\_allocated\_storage) | Initial allocated storage in GiB. | `number` | `20` | no |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | CIDR blocks allowed to connect to the database. | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | Security group IDs allowed to connect to the database. | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply changes immediately instead of during the next maintenance window. | `bool` | `false` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | Apply minor version upgrades automatically during the maintenance window. | `bool` | `true` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Days to retain automated backups (0 to disable, max 35). | `number` | `7` | no |
| <a name="input_backup_window"></a> [backup\_window](#input\_backup\_window) | Daily time range for automated backups (UTC). Format: hh:mm-hh:mm. | `string` | `"03:00-04:00"` | no |
| <a name="input_db_instance_tags"></a> [db\_instance\_tags](#input\_db\_instance\_tags) | Tags applied to the DB instance only, on top of provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Name of the initial database to create. | `string` | `"appdb"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Prevent accidental deletion of the instance. | `bool` | `true` | no |
| <a name="input_enabled_cloudwatch_logs_exports"></a> [enabled\_cloudwatch\_logs\_exports](#input\_enabled\_cloudwatch\_logs\_exports) | List of log types to export to CloudWatch. Valid values for PostgreSQL: 'postgresql', 'upgrade'. | `list(string)` | <pre>[<br/>  "postgresql",<br/>  "upgrade"<br/>]</pre> | no |
| <a name="input_engine"></a> [engine](#input\_engine) | RDS engine name. | `string` | `"postgres"` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | PostgreSQL major version (e.g. '16'). Minor version is auto-selected when auto\_minor\_version\_upgrade is true. | `string` | `"16"` | no |
| <a name="input_final_snapshot_identifier"></a> [final\_snapshot\_identifier](#input\_final\_snapshot\_identifier) | Name for the final snapshot on deletion. If empty, defaults to '{identifier}-final'. | `string` | `""` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Unique identifier for the RDS instance. Used for naming all associated resources. | `string` | n/a | yes |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | RDS instance class (e.g. 'db.m5.large', 'db.t3.medium'). Validated against orderable combinations at plan time. | `string` | `"db.t3.medium"` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | KMS key ARN for storage encryption. Uses default aws/rds key if not specified. | `string` | `null` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Weekly maintenance window (UTC). Format: ddd:hh:mm-ddd:hh:mm. | `string` | `"sun:05:00-sun:06:00"` | no |
| <a name="input_master_user_secret_kms_key_id"></a> [master\_user\_secret\_kms\_key\_id](#input\_master\_user\_secret\_kms\_key\_id) | KMS key for a Secrets Manager-managed master password. When set, credentials are managed by Secrets Manager and 'password' must not be provided. | `string` | `null` | no |
| <a name="input_max_allocated_storage"></a> [max\_allocated\_storage](#input\_max\_allocated\_storage) | Maximum storage in GiB for autoscaling. Set to 0 to disable. | `number` | `40` | no |
| <a name="input_multi_az"></a> [multi\_az](#input\_multi\_az) | Enable Multi-AZ deployment for high availability. | `bool` | `false` | no |
| <a name="input_parameter_group_name"></a> [parameter\_group\_name](#input\_parameter\_group\_name) | Existing DB parameter group to attach. Uses the engine default if null. | `string` | `null` | no |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | Parameter name to value. When non-empty, creates and attaches a parameter group (pending-reboot). | `map(string)` | `{}` | no |
| <a name="input_password"></a> [password](#input\_password) | Master password. Used only when master\_user\_secret\_kms\_key\_id is not set. Mutually exclusive with it. Ephemeral: never written to state or plan (delivered via the write-only password\_wo argument). | `string` | `null` | no |
| <a name="input_password_wo_version"></a> [password\_wo\_version](#input\_password\_wo\_version) | Bump to rotate the write-only password. Only relevant in password mode. | `number` | `1` | no |
| <a name="input_performance_insights_enabled"></a> [performance\_insights\_enabled](#input\_performance\_insights\_enabled) | Enable Performance Insights. | `bool` | `true` | no |
| <a name="input_port"></a> [port](#input\_port) | Port the PostgreSQL server listens on. | `number` | `5432` | no |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | Existing security group ID to use instead of creating one. When set, the module skips SG creation and all ingress/egress rule management — manage rules on the external group. Mutually exclusive with allowed\_cidrs and allowed\_security\_group\_ids. | `string` | `null` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Skip final snapshot on deletion. Keep false so a snapshot is taken before destroy. | `bool` | `false` | no |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | DB snapshot to restore from on create (e.g. for wake-from-sleep). Empty string means create fresh. | `string` | `""` | no |
| <a name="input_storage_encrypted"></a> [storage\_encrypted](#input\_storage\_encrypted) | Whether to encrypt storage at rest. | `bool` | `true` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage\_type) | Storage type: 'gp3', 'io1', 'io2'. | `string` | `"gp3"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for the DB subnet group (data tier). At least 2 subnets in different AZs are required by RDS. | `list(string)` | n/a | yes |
| <a name="input_username"></a> [username](#input\_username) | Master username for the database. | `string` | `"dbadmin"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the security group will be created. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_address"></a> [address](#output\_address) | Hostname of the RDS instance. |
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the RDS instance. |
| <a name="output_db_instance_id"></a> [db\_instance\_id](#output\_db\_instance\_id) | RDS instance identifier. |
| <a name="output_db_name"></a> [db\_name](#output\_db\_name) | The database name. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Connection endpoint in address:port format. |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | ARN of the Secrets Manager secret containing the master user credentials. |
| <a name="output_parameter_group_name"></a> [parameter\_group\_name](#output\_parameter\_group\_name) | Name of the attached DB parameter group (existing or module-created), or null for the engine default. |
| <a name="output_port"></a> [port](#output\_port) | Database port. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the security group used by the RDS instance (created or caller-provided). |
| <a name="output_username"></a> [username](#output\_username) | The master username for the database. |
<!-- END_TF_DOCS -->
