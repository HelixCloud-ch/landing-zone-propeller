# msk-connect-debezium

Shared Terraform module that stands up a single Debezium change-data-capture
connector on Amazon MSK Connect. It creates the connector security group, the
service execution IAM role and its scoped policy, a CloudWatch log group, an
MSK Connect worker configuration, the MSK Connect connector itself, and a
not-in-running-state CloudWatch alarm. The per-engine Debezium configuration is
supplied by a template under `config/<engine>.tftpl` — `mariadb` and `oracle`
both exist; **Oracle is unverified against real infrastructure**, see
[Oracle](#oracle) below. The module takes plain AWS inputs — IDs, ARNs,
hostnames, topic names — and knows nothing about propeller's input shapes, so it
is usable on its own as well as through the
`platform/projects/msk-connect-debezium` project that adapts propeller
conventions onto it.

## Which runner and why

A consumer wiring this module into a pipeline must run it on the **Egress
Runner**. The module creates an IAM role and role policy, and IAM is a global
service the in-VPC runner cannot reach; only the egress runner can. This is a
property of the resources the module creates, so it holds for any consumer, not
just the project.

## Connector immutability and replace-on-plugin-change

MSK Connect connectors are immutable with respect to their plugin. Changing
`custom_plugin_arn` — which happens on a Debezium version bump — therefore
**replaces** the connector rather than updating it in place. The connector sets
`create_before_destroy` so the new connector is created before the old one is
removed, but a replacement still implies a CDC gap: while the old connector is
torn down and the new one starts and re-establishes its position, no changes are
captured. If the offset topic is lost or unreadable across the bump, the new
connector cannot resume from the recorded position and performs a full
re-snapshot of the source (Req 5.16). Treat a plugin bump as an operational
event, not a routine apply.

## Security group

The connector's ENIs live in `subnet_ids`, which must reach both the source
database (`db_port`) and the Kafka brokers (`broker_port`). The module opens
exactly those two egress ports; ingress is not needed because the connector only
initiates outbound connections.

## Service execution role and policy

The role is assumed by `kafkaconnect.amazonaws.com` and is constrained by two
confused-deputy conditions: `aws:SourceAccount` pins the calling account, and
`aws:SourceArn` pins connectors of this name in this account and region. The
connector ARN carries a random suffix generated at create time and so cannot be
pinned exactly, which is why the `SourceArn` condition uses a name-scoped
wildcard — see the accepted checkov findings below.

The attached policy grants `ssm:GetParameter` on **exactly** the two credential
parameter ARNs passed in, and nothing wider. Kafka data-plane permissions depend
on `client_authentication`: with `NONE` the connector authenticates at the
transport layer and the policy grants **no** `kafka-cluster:*` permissions; with
`IAM` the policy adds cluster-level actions (`Connect`, `AlterCluster`,
`DescribeCluster`) plus topic and group actions, each scoped to the target
cluster's ARN and its derived topic/group ARNs.

## Worker configuration and the SSM Config Provider

The worker configuration declares the offset topic and registers the AWS SSM
parameter-store Config Provider under the alias `ssm`. The connector config
(rendered from the engine template) references the CDC credentials as
`${ssm::<parameter-name>}` placeholders that MSK Connect resolves at connector
start by reading the named SSM parameters. The credential **values** are never
interpolated by Terraform and never enter Terraform state or the plan — only the
parameter *names* do. `config.action.reload=none` keeps a parameter change from
silently restarting the connector.

The username and password live in **two separate scalar parameters**
(`cdc_username_parameter`, `cdc_password_parameter`), one `${ssm::…}` reference
each for `database.user` and `database.password`. This is a hard constraint of
the SSM Config Provider, not a preference: it resolves a placeholder to the
parameter's **entire value** and cannot extract a key out of a JSON document
(only the Secrets Manager provider can). A single JSON `{username, password}`
parameter would therefore not work here. The upstream
[`cdc-prepare-mariadb`](../../../projects/cdc-prepare-mariadb/README.md) /
[`cdc-prepare-oracle`](../../../projects/cdc-prepare-oracle/README.md) projects
create exactly these two scalar `SecureString` parameters. See
[Tutorial: Externalizing sensitive information using config providers](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-config-provider.html).

### Decrypting the SecureString parameters

Because the parameters are `SecureString`, reading them calls `kms:Decrypt`.
The service execution role's grant depends on which key encrypts them, supplied
as `cdc_kms_key_id` (an alias name, key id, or key ARN):

- **Default AWS-managed key (`alias/aws/ssm`, the default).** No `kms:Decrypt`
  statement is added. Access to the AWS-managed SSM key is implicit for a
  principal already allowed `ssm:GetParameter`, and the key cannot be named as
  an IAM `Resource` anyway.
- **Customer-managed key.** The module resolves the supplied alias/id/ARN to
  the key's **real ARN** with an `aws_kms_key` data source (an IAM `Resource`
  for a cryptographic action must be a key ARN, never an alias ARN) and grants
  `kms:Decrypt` scoped to exactly that key.

See [AWS KMS encryption for SecureString parameters](https://docs.aws.amazon.com/systems-manager/latest/userguide/secure-string-parameter-kms-encryption.html).

## Connector

Provisioned capacity with one worker. `client_authentication` (`NONE` | `IAM`)
and `in_transit_encryption` (`PLAINTEXT` | `TLS`) are independent inputs with no
built-in assumption about which combination a cluster uses — a consumer sets both
to match its cluster. `server_id` (Debezium `database.server.id`) is derived
deterministically per connector by the caller so it is stable across applies and
distinct across connectors. `topic_prefix` is effectively immutable: changing it
orphans the existing topics and breaks schema-history recovery, so it should be
treated as fixed for the life of the connector.

## Oracle

> **Unverified against real infrastructure.** `config/oracle.tftpl` is
> written and offline-tested (rendering only — no connector has ever been
> deployed against a live Oracle source). See
> [`cdc-prepare-oracle`](../../../projects/cdc-prepare-oracle/README.md) for the
> database-side preparation this connector depends on, and
> [`docs/cdc-deployment-verification.md`](../../../../docs/cdc-deployment-verification.md#oracle)
> before any production use.

`engine = "oracle"` selects `config/oracle.tftpl`, which sets
`connector.class=io.debezium.connector.oracle.OracleConnector` and three
inputs the MariaDB template does not use:

- **`db_name`** — the Oracle service name / SID (`database.dbname`). On a CDB
  instance this is the container database's service.
- **`pdb_name`** — the pluggable database name (`database.pdb.name`), for a
  multitenant (CDB) source. Empty (default) omits the property entirely,
  because a non-CDB instance has no PDB to name — the same
  omit-rather-than-emit-empty convention `table_include_list` already uses.
- **`log_mining_strategy`** — Oracle LogMiner's `log.mining.strategy`,
  defaulting to `hybrid`.

### Choosing `log_mining_strategy`

Debezium's Oracle connector documents three strategies for how LogMiner
builds and uses its data dictionary to resolve table and column names:

| Strategy | Tracks DDL? | Extra archive-log volume? | Notes |
| -------- | :---------: | :------------------------: | ----- |
| `redo_log_catalog` | yes | yes — writes the dictionary into the online redo logs | **Deprecated, scheduled for removal** in a future Debezium release |
| `online_catalog` | no | no | Fastest; only safe when captured tables' schema changes infrequently or never |
| `hybrid` | yes | no | Combines the current data dictionary with Debezium's in-memory schema model: `online_catalog`'s speed with `redo_log_catalog`'s DDL-tracking resilience |

The module defaults to **`hybrid`** deliberately, not to whichever value
happens to be the connector's own default (which has changed across Debezium
series — `redo_log_catalog` in 2.7, `online_catalog` from 3.0 onward as of
this writing). `hybrid` is available in every Debezium series this framework
catalogues (`msk-connect-plugin-artifact/versions.json`) and gives DDL
tracking without `redo_log_catalog`'s archive-log growth — the better choice
on the small instances this framework targets, where LogMiner's own CPU
impact on the source is already the primary open risk (see
`docs/cdc-deployment-verification.md`).

### A known open risk

The community has reported `ORA-01031` (insufficient privileges) against RDS
for Oracle **CDB** instances specifically, even with every grant
`cdc-prepare-oracle` issues in place, because the root-container-level
privileges Debezium's connector needs cannot always be granted the same way
on RDS as on a self-managed Oracle instance. This has not been resolved or
tested against a real RDS for Oracle CDB instance — it is exactly the kind of
gap `docs/cdc-deployment-verification.md`'s Oracle section exists to close
before production use.

## Log group and alarm

The log group has an explicit, finite, consumer-overridable retention
(`log_retention_in_days`, default 30). The not-running alarm fires when the
connector's running task count drops below one; its `alarm_actions` default to an
empty list because the framework has no notification-target convention yet, so a
consumer supplies actions once one exists. Note that the alarm fires for the
whole duration of any sleep window, since a slept connector is not running.

### Accepted checkov findings

Two findings are accepted with justification (see the inline `checkov:skip`
comments), not fixed:

- **Log group retention (CKV_AWS_338).** Retention is a deliberate, finite,
  overridable input rather than an enforced long minimum, consistent with how
  the MSK cluster's own log group is configured.
- **Service execution role `SourceArn` wildcard.** The connector ARN is not
  knowable before create (random suffix), so the assume-role `SourceArn`
  condition is a name-scoped wildcard. Confused-deputy protection is still
  provided by the `SourceAccount` condition.

The empty `alarm_actions` default is intentional for the reason above.

## Sleep/wake and teardown constraints

Implementing sleep/wake for CDC is **out of scope** for this module — the
consumer wiring the pipeline owns that decision. The module documents the
constraints only:

- **Teardown ordering.** The connector must be removed *before* its source
  database and *before* its Kafka cluster. It reads from both; tearing either
  down first leaves the connector failing.
- **MSK sleep is destroy-only.** Under the framework's MSK sleep semantics,
  sleeping the cluster destroys it, so a sleeping cluster loses its topics and
  its consumer offsets. On wake the Topics project must run again to
  recreate the topics **before** the connector is recreated; the connector then
  performs a recovery snapshot because its offset and schema-history state is
  gone.
- **Binary-log retention window.** A sleep that outlasts the source database's
  configured binary-log retention window turns what would have been a bounded
  CDC gap into a full re-snapshot, because the binlog positions the connector
  would resume from have aged out.

No sleep/wake recipe is implemented here.

## Consumed by

`platform/projects/msk-connect-debezium` is a thin propeller adapter around this
module. The module itself is standalone: give it plain AWS inputs and it works
under a bare `terraform apply` or any non-propeller consumer.

## References

- [MSK Connect connectors](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-connectors.html)
- [MSK Connect and IAM: service execution role](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-service-execution-role.html)
- [Externalizing sensitive information with config providers](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-config-providers.html)
- [Debezium connector for MariaDB](https://debezium.io/documentation/reference/stable/connectors/mariadb.html)
- [Debezium connector for Oracle](https://debezium.io/documentation/reference/stable/connectors/oracle.html) — `log.mining.strategy` options.
- [aws_mskconnect_connector Terraform resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mskconnect_connector)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.connector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.not_running](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_role.connector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.connector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_mskconnect_connector.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mskconnect_connector) | resource |
| [aws_mskconnect_worker_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mskconnect_worker_configuration) | resource |
| [aws_security_group.connector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.brokers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.connector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_kms_key.cdc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_key) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alarm_actions"></a> [alarm\_actions](#input\_alarm\_actions) | Actions for the not-running alarm (e.g. SNS topic ARNs). Defaults to empty: the framework has no notification-target convention yet. | `list(string)` | `[]` | no |
| <a name="input_bootstrap_servers"></a> [bootstrap\_servers](#input\_bootstrap\_servers) | Kafka bootstrap servers string the connector and the schema-history writer connect to. | `string` | n/a | yes |
| <a name="input_broker_port"></a> [broker\_port](#input\_broker\_port) | Kafka broker port the connector connects to. Opened as an egress rule on the connector security group. | `number` | `9098` | no |
| <a name="input_cdc_kms_key_id"></a> [cdc\_kms\_key\_id](#input\_cdc\_kms\_key\_id) | KMS key that encrypts the two CDC SecureString parameters, as an alias<br/>name, key id, or key ARN. Determines whether the service execution role<br/>needs kms:Decrypt: the default AWS-managed key (alias/aws/ssm) grants<br/>decrypt implicitly and cannot be named in an IAM Resource, so no statement<br/>is added; any other (customer-managed) key is resolved to its real key ARN<br/>and granted kms:Decrypt. See README. | `string` | `"alias/aws/ssm"` | no |
| <a name="input_cdc_password_parameter"></a> [cdc\_password\_parameter](#input\_cdc\_password\_parameter) | Name of the SSM parameter holding the CDC user password. Referenced literally in the connector config via the SSM Config\_Provider. | `string` | n/a | yes |
| <a name="input_cdc_password_parameter_arn"></a> [cdc\_password\_parameter\_arn](#input\_cdc\_password\_parameter\_arn) | ARN of the CDC password SSM parameter. The service execution role is granted ssm:GetParameter on exactly this ARN. | `string` | n/a | yes |
| <a name="input_cdc_username_parameter"></a> [cdc\_username\_parameter](#input\_cdc\_username\_parameter) | Name of the SSM parameter holding the CDC user name. Referenced literally in the connector config via the SSM Config\_Provider. | `string` | n/a | yes |
| <a name="input_cdc_username_parameter_arn"></a> [cdc\_username\_parameter\_arn](#input\_cdc\_username\_parameter\_arn) | ARN of the CDC username SSM parameter. The service execution role is granted ssm:GetParameter on exactly this ARN. | `string` | n/a | yes |
| <a name="input_client_authentication"></a> [client\_authentication](#input\_client\_authentication) | MSK Connect client authentication. NONE grants no kafka-cluster permissions; IAM adds them. SASL/SCRAM is unavailable to a connector. | `string` | `"NONE"` | no |
| <a name="input_custom_plugin_arn"></a> [custom\_plugin\_arn](#input\_custom\_plugin\_arn) | ARN of the registered MSK Connect custom plugin. Changing it forces connector replacement (MSK Connect connectors are immutable wrt their plugin). | `string` | n/a | yes |
| <a name="input_custom_plugin_revision"></a> [custom\_plugin\_revision](#input\_custom\_plugin\_revision) | Revision of the custom plugin to pin. Defaults to 1, the revision an MSK Connect custom plugin is created with. | `number` | `1` | no |
| <a name="input_db_host"></a> [db\_host](#input\_db\_host) | Hostname of the source database the connector reads from. | `string` | n/a | yes |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Oracle service name / SID (database.dbname). Ignored by the mariadb template. On a CDB instance this is the container database's service; see pdb\_name to target a pluggable database instead. | `string` | `""` | no |
| <a name="input_db_port"></a> [db\_port](#input\_db\_port) | Port of the source database. Opened as an egress rule on the connector security group. | `number` | `3306` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | Source engine. Selects the connector config template config/<engine>.tftpl. | `string` | `"mariadb"` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Unique connector identifier. Names all associated resources and seeds the deterministic Debezium server id. | `string` | n/a | yes |
| <a name="input_in_transit_encryption"></a> [in\_transit\_encryption](#input\_in\_transit\_encryption) | Encryption in transit to the cluster: PLAINTEXT or TLS. Independent of client\_authentication, with no built-in assumption. | `string` | `"PLAINTEXT"` | no |
| <a name="input_kafka_cluster_arn"></a> [kafka\_cluster\_arn](#input\_kafka\_cluster\_arn) | ARN of the target MSK cluster. Scopes the kafka-cluster:* grants when client\_authentication is IAM. | `string` | n/a | yes |
| <a name="input_kafkaconnect_version"></a> [kafkaconnect\_version](#input\_kafkaconnect\_version) | Kafka Connect version for the connector. MSK Connect supports 2.7.1 and 3.7.x only. | `string` | `"3.7.x"` | no |
| <a name="input_log_mining_strategy"></a> [log\_mining\_strategy](#input\_log\_mining\_strategy) | Oracle LogMiner's log.mining.strategy. Ignored by the mariadb template.<br/>'hybrid' (default) tracks DDL changes without the extra archive-log<br/>volume 'redo\_log\_catalog' generates, and is the currently-recommended<br/>replacement for 'redo\_log\_catalog', which is deprecated and scheduled<br/>for removal in a future Debezium release. 'online\_catalog' mines faster<br/>but cannot track DDL changes against captured tables — choose it only<br/>when the captured tables' schema changes infrequently or never. See the<br/>module README for the full tradeoff. | `string` | `"hybrid"` | no |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | Retention for the connector log group. Finite by default, overridable by the consumer. | `number` | `30` | no |
| <a name="input_offset_topic"></a> [offset\_topic](#input\_offset\_topic) | Kafka topic where the connector stores source offsets. Declared in the worker configuration. | `string` | n/a | yes |
| <a name="input_pdb_name"></a> [pdb\_name](#input\_pdb\_name) | Oracle pluggable database name (database.pdb.name), for a multitenant (CDB) source. Empty (default) omits the property entirely — a non-CDB instance has no PDB to name. Ignored by the mariadb template. | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region as a literal, used for the SSM Config\_Provider in the worker configuration. Passed by the project from its own region variable. | `string` | n/a | yes |
| <a name="input_schema_history_topic"></a> [schema\_history\_topic](#input\_schema\_history\_topic) | Kafka topic where Debezium stores captured schema history. | `string` | n/a | yes |
| <a name="input_server_id"></a> [server\_id](#input\_server\_id) | Debezium database.server.id. Must be stable per connector and unique across connectors; the project derives it deterministically from identifier. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs the connector's ENIs are placed in. Must reach the database and the Kafka brokers. | `list(string)` | n/a | yes |
| <a name="input_table_include_list"></a> [table\_include\_list](#input\_table\_include\_list) | Comma-separated Debezium table.include.list. Empty string captures everything: the template omits the property entirely rather than emitting a wildcard. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to resources that take a tags map. The project passes the merged tag set; the module does not know propeller's tag triple. | `map(string)` | `{}` | no |
| <a name="input_topic_prefix"></a> [topic\_prefix](#input\_topic\_prefix) | Debezium topic prefix. Effectively immutable: changing it orphans existing topics and breaks schema-history recovery. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the connector security group is created. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alarm_arn"></a> [alarm\_arn](#output\_alarm\_arn) | ARN of the connector not-running CloudWatch alarm. |
| <a name="output_connector_arn"></a> [connector\_arn](#output\_connector\_arn) | ARN of the MSK Connect connector. The project re-exports this as its own Terraform output. |
| <a name="output_connector_name"></a> [connector\_name](#output\_connector\_name) | Name of the MSK Connect connector. |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Name of the CloudWatch log group receiving connector logs. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the security group attached to the connector's ENIs. |
| <a name="output_service_execution_role_arn"></a> [service\_execution\_role\_arn](#output\_service\_execution\_role\_arn) | ARN of the connector's service execution role. |
| <a name="output_worker_configuration_arn"></a> [worker\_configuration\_arn](#output\_worker\_configuration\_arn) | ARN of the connector's worker configuration. |
<!-- END_TF_DOCS -->
