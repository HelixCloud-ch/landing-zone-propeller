# MSK Connect Debezium

A thin propeller adapter that provisions one Debezium change-data-capture
connector on MSK Connect via the shared module
[`platform/shared/modules/msk-connect-debezium`](../../shared/modules/msk-connect-debezium/README.md).
The project decodes the propeller inputs — the credential-parameter names/ARNs
blob and the tables list — and derives the deterministic Debezium
`database.server.id` from the connector identifier, then passes plain AWS data
to the module. All resource logic lives in the module; this project is glue.

## What it deploys

Nothing directly. The project holds locals that adapt propeller conventions and
a single `module` block over the shared module, which owns every resource: the
connector security group, the service execution IAM role and its scoped policy,
the CloudWatch log group, the MSK Connect worker configuration, the connector
itself, and the not-in-running-state alarm. See the
[module README](../../shared/modules/msk-connect-debezium/README.md) for the
resource-level detail — it is not repeated here.

## Runner

Runs on the **Egress_Runner**. The module it wraps creates an IAM role (the
connector's service execution role), and IAM is a global service the in-VPC
runner cannot reach; only the egress runner can. This is a property of the
resources the module creates, so it holds regardless of how the project is
wired.

## Debezium version bump replaces the connector

MSK Connect connectors are immutable with respect to their plugin. A Debezium
version bump changes the resolved plugin ARN, which **replaces** the connector
rather than updating it in place — it is not a routine apply. A replacement
implies a **CDC gap** while the old connector is torn down and the new one
starts and re-establishes its position, and if the offset topic is lost or
unreadable across the bump the new connector performs a full re-snapshot of the
source. See
[the module README](../../shared/modules/msk-connect-debezium/README.md#connector-immutability-and-replace-on-plugin-change)
for the full behaviour and the `create_before_destroy` handling.

## Pipeline wiring

```yaml
stages:
  - name: cdc-connector
    steps:
      - project: msk-connect-debezium
        source: propeller:msk-connect-debezium
        target: workload-account
        runner: egress-runner
        depends_on:
          - msk-connect-plugin
          - cdc-prepare-mariadb
          - cdc-topics
        inputs:
          - name: msk-connect-plugin.default_plugin_arns
            var: default_plugin_arns
          - name: msk-connect-plugin.default_plugin_revisions
            var: default_plugin_revisions
          - name: msk-connect-plugin.plugin_arns
            var: plugin_arns
          - name: msk-connect-plugin.plugin_revisions
            var: plugin_revisions
          - var: cdc_username_parameter
            literal: "/platform/myapp/cdc-username"
          - var: cdc_password_parameter
            literal: "/platform/myapp/cdc-password"
          - name: cdc-topics.offset_topic
            var: offset_topic
          - name: cdc-topics.schema_history_topic
            var: schema_history_topic
        outputs:
          - name: msk-connect-debezium.connector_arn
            var: connector_arn
```

The plugin maps come whole from `msk-connect-plugin` — the pipeline passes them
as-is because a propeller input reads a whole output field and cannot pick a map
key (see [`docs/pipeline-schema.md`](../../../docs/pipeline-schema.md) §
Path resolution). This project selects the entry itself by `engine` (the
flavour) plus an optional `plugin_version` (see
[Plugin selection](#plugin-selection)). The topic names come from
`cdc-topics`. The two credential parameter *names* are the same names given to
`cdc-prepare-mariadb` — the prep project emits no output (it only writes the
SSM parameters), so the names are supplied to both steps by the pipeline author
(a shared literal or YAML anchor keeps them in one place). This project derives
each parameter's ARN itself and never reads the parameter *value*. The step
runs on the egress runner (see [Runner](#runner)) and depends on all three
upstream steps. Field and namespace forms follow
[`docs/pipeline-schema.md`](../../../docs/pipeline-schema.md).

## Plugin selection

`msk-connect-plugin` publishes its plugins as **maps**: `default_plugin_arns` /
`default_plugin_revisions` keyed by flavour (`{ mariadb = ..., oracle = ... }`),
and `plugin_arns` / `plugin_revisions` keyed by `<flavour>-<version>`
(`{ "mariadb-2.7.4.Final" = ... }`). The connector needs a single ARN, so one
entry must be chosen — and the choice is made **here**, not in the pipeline,
because a propeller input reference reads a whole output field and cannot address
a map key.

The selection reuses `engine` as the flavour:

- **`plugin_version` empty (default)** → the flavour's current default:
  `default_plugin_arns[engine]` / `default_plugin_revisions[engine]`. Wiring the
  pipeline never changes on a version bump; the plugin project's `default_versions`
  decides what "current" means.
- **`plugin_version` set** (e.g. `2.7.4.Final`) → a pinned version:
  `plugin_arns["<engine>-<plugin_version>"]` / the matching revision. Use this to
  run an explicit version, e.g. to stay on the old plugin while cutting over, or
  to move ahead of the default.

A `validation` on `plugin_version` asserts the chosen key exists in the relevant
map at plan time, so a typo or an unregistered version fails before any apply
rather than at connector creation.

## Inputs

The [generated block](#requirements) below carries the full table; this section
notes only the propeller-facing shape and the non-obvious values.

- **`identifier`** — unique connector identifier; names the module resources and
  seeds the derived `server_id`.
- **`vpc_id`, `subnet_ids`** — where the connector ENIs live; must reach both
  the database and the brokers.
- **`db_host`, `db_port`** — source database the connector reads from.
- **`bootstrap_servers`, `broker_port`** — Kafka endpoint the connector writes
  to.
- **`plugin_arns`, `plugin_revisions`, `default_plugin_arns`,
  `default_plugin_revisions`** — the four plugin maps from `msk-connect-plugin`,
  passed whole. The project selects one entry (see
  [Plugin selection](#plugin-selection)); the resolved plugin replaces the
  connector when it changes (see above).
- **`plugin_version`** — optional. Empty (default) uses the `engine`'s default
  plugin; a value like `2.7.4.Final` pins `"<engine>-<version>"`. See
  [Plugin selection](#plugin-selection).
- **`kafka_cluster_arn`** — scopes the `kafka-cluster:*` grants when
  `client_authentication` is `IAM`.
- **`client_authentication`** (`NONE` | `IAM`), **`in_transit_encryption`**
  (`PLAINTEXT` | `TLS`) — independent knobs matched to the target cluster.
- **`offset_topic`, `schema_history_topic`, `topic_prefix`** — the connector's
  Kafka topics; `topic_prefix` is effectively immutable.
- **`cdc_username_parameter`, `cdc_password_parameter`** — the *names* of the two
  scalar `SecureString` parameters `cdc-prepare-mariadb` / `cdc-prepare-oracle`
  create (one for the username, one for the password), e.g.
  `/platform/myapp/cdc-username` and `/platform/myapp/cdc-password`. You pass the
  same names you gave the prep step. Two scalar parameters — not one JSON
  document — because the SSM Config Provider cannot extract a key out of JSON
  (see the
  [module README](../../shared/modules/msk-connect-debezium/README.md#worker-configuration-and-the-ssm-config-provider)).
  The project derives each parameter's **ARN** locally from account/region/
  partition (an `aws_caller_identity` + `aws_partition` lookup — it never reads
  the parameter *value*, so no secret enters Terraform state) and passes name +
  ARN to the module. The ARN scopes the connector role's `ssm:GetParameter`.
- **`cdc_kms_key_id`** — the KMS key encrypting those two parameters
  (alias/id/ARN). Default `alias/aws/ssm` adds no `kms:Decrypt` to the
  connector role; a customer-managed key is resolved to its real ARN and
  granted `kms:Decrypt`. See the
  [module README](../../shared/modules/msk-connect-debezium/README.md#decrypting-the-securestring-parameters).
- **`tables`** — a JSON list of fully-qualified tables, joined into the module's
  `table_include_list`; an empty list (`"[]"`, the default) captures everything.
- **`engine`** — selects the module's config template (`mariadb` or `oracle`;
  **Oracle is unverified against real infrastructure** — see the
  [module README's Oracle section](../../shared/modules/msk-connect-debezium/README.md#oracle)).
- **`db_name`, `pdb_name`** — Oracle-only; ignored for `engine = "mariadb"`.
  `db_name` is the Oracle service name / SID; `pdb_name` names a pluggable
  database on a multitenant (CDB) source and is omitted entirely when empty.
- **`log_mining_strategy`** — Oracle-only; ignored for `engine = "mariadb"`.
  Defaults to `hybrid`; see the module README for the tradeoff against
  `online_catalog` and the deprecated `redo_log_catalog`.
- **`log_retention_in_days`, `alarm_actions`** — passed through to the module.
- **`server_id`** — optional. Leave `null` to derive it deterministically from
  `identifier`: the project folds the top 32 bits of `sha256(identifier)` into
  the MariaDB `1..4294967295` range, so it is stable per connector and distinct
  across connectors.

## Outputs

- **`connector_arn`** — ARN of the connector, consumed by any downstream app or
  monitoring.
- **`connector_name`, `service_execution_role_arn`, `security_group_id`** —
  re-exported module outputs.
- **`server_id`** — the `database.server.id` in effect (supplied or derived).

## Idempotency and destroy

`plan`, `apply` and `destroy` are the standard Terraform recipes (`tf-plan`,
`tf-apply`, `tf-destroy` from `shared/recipes/terraform.just`); there is no
custom lifecycle logic. `destroy` removes the connector and its supporting
resources, and must happen **before** the source database and the Kafka cluster
are torn down — the connector reads from both, so tearing either down first
leaves it failing (see the ordering below).

## Sleep/wake and teardown

No sleep/wake recipe is implemented for any CDC project — the consumer wiring
the pipeline owns that decision, and these projects document the constraints
only. The constraints below concern the CDC chain as a whole and are repeated on
every CDC project's README so the ordering is visible wherever an operator
starts:

- **Teardown ordering.** The connector must be removed **before** its source
  database and its Kafka cluster.
- **MSK sleep is destroy-only.** Under the framework's MSK sleep semantics, a
  sleeping cluster loses its topics and consumer offsets, so on wake the Topics
  project (`cdc-topics`) must run again to
  recreate the topics **before** the connector is recreated; the connector then
  performs a recovery snapshot because its offset and schema-history state is
  gone.
- **Binary-log retention window.** A sleep that outlasts the source database's
  configured binary-log retention window turns a bounded CDC gap into a full
  re-snapshot, because the binlog positions the connector would resume from have
  aged out.
- **Alarm during sleep.** The not-in-running-state alarm fires for the whole
  duration of any sleep window, since a slept connector is not running.

## What does NOT belong here

- **The resource logic** — it lives in the shared module
  ([`platform/shared/modules/msk-connect-debezium`](../../shared/modules/msk-connect-debezium/README.md)),
  which this project only adapts propeller inputs onto.
- **Registering the plugin** — that is `msk-connect-plugin`.
- **Preparing the source database** — that is `cdc-prepare-mariadb`.
- **Creating the Kafka topics** — that is `cdc-topics`.

## References

- [Module README — `msk-connect-debezium`](../../shared/modules/msk-connect-debezium/README.md)
- [`docs/pipeline-schema.md`](../../../docs/pipeline-schema.md)
- [Terraform `aws_mskconnect_connector`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mskconnect_connector)
- [AWS — MSK Connect connectors](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-connectors.html)

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

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_debezium"></a> [debezium](#module\_debezium) | ../../../shared/modules/msk-connect-debezium | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alarm_actions"></a> [alarm\_actions](#input\_alarm\_actions) | Actions for the connector not-running alarm (e.g. SNS topic ARNs). Empty by default. | `list(string)` | `[]` | no |
| <a name="input_bootstrap_servers"></a> [bootstrap\_servers](#input\_bootstrap\_servers) | Kafka bootstrap servers string the connector connects to. | `string` | n/a | yes |
| <a name="input_broker_port"></a> [broker\_port](#input\_broker\_port) | Kafka broker port. Opened as connector egress. | `number` | `9098` | no |
| <a name="input_cdc_kms_key_id"></a> [cdc\_kms\_key\_id](#input\_cdc\_kms\_key\_id) | KMS key encrypting the CDC SecureString parameters (alias/id/ARN). Default alias/aws/ssm adds no kms:Decrypt; a customer-managed key is resolved to its ARN and granted. See module README. | `string` | `"alias/aws/ssm"` | no |
| <a name="input_cdc_password_parameter"></a> [cdc\_password\_parameter](#input\_cdc\_password\_parameter) | Name of the SSM parameter holding the CDC password (created by cdc-prepare-*). The project derives its ARN for the connector's IAM policy; the module reads the value at connector-start via the SSM Config Provider. | `string` | n/a | yes |
| <a name="input_cdc_username_parameter"></a> [cdc\_username\_parameter](#input\_cdc\_username\_parameter) | Name of the SSM parameter holding the CDC username (created by cdc-prepare-*). The project derives its ARN for the connector's IAM policy; the module reads the value at connector-start via the SSM Config Provider. | `string` | n/a | yes |
| <a name="input_client_authentication"></a> [client\_authentication](#input\_client\_authentication) | MSK Connect client authentication: NONE (no kafka-cluster grants) or IAM (adds them). | `string` | `"NONE"` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_db_host"></a> [db\_host](#input\_db\_host) | Hostname of the source database the connector reads from. | `string` | n/a | yes |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Oracle service name / SID (database.dbname). Ignored for engine = "mariadb". | `string` | `""` | no |
| <a name="input_db_port"></a> [db\_port](#input\_db\_port) | Port of the source database. Opened as connector egress. | `number` | `3306` | no |
| <a name="input_default_plugin_arns"></a> [default\_plugin\_arns](#input\_default\_plugin\_arns) | Custom plugin ARNs of the default version, keyed by flavour (msk-connect-plugin.default\_plugin\_arns). Used when plugin\_version is empty. | `map(string)` | `{}` | no |
| <a name="input_default_plugin_revisions"></a> [default\_plugin\_revisions](#input\_default\_plugin\_revisions) | Custom plugin revisions of the default version, keyed by flavour (msk-connect-plugin.default\_plugin\_revisions). Used when plugin\_version is empty. | `map(number)` | `{}` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | Source engine selecting the module's config template. | `string` | `"mariadb"` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Unique connector identifier. Names all module resources and seeds the deterministic Debezium server id. | `string` | n/a | yes |
| <a name="input_in_transit_encryption"></a> [in\_transit\_encryption](#input\_in\_transit\_encryption) | Encryption in transit to the cluster: PLAINTEXT or TLS. | `string` | `"PLAINTEXT"` | no |
| <a name="input_kafka_cluster_arn"></a> [kafka\_cluster\_arn](#input\_kafka\_cluster\_arn) | ARN of the target MSK cluster. Scopes the kafka-cluster:* grants when client\_authentication is IAM. | `string` | n/a | yes |
| <a name="input_log_mining_strategy"></a> [log\_mining\_strategy](#input\_log\_mining\_strategy) | Oracle LogMiner's log.mining.strategy. Ignored for engine = "mariadb". See the module README for the tradeoff between 'hybrid' (default), 'online\_catalog' and the deprecated 'redo\_log\_catalog'. | `string` | `"hybrid"` | no |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | Retention for the connector log group. Passed through to the module. | `number` | `30` | no |
| <a name="input_offset_topic"></a> [offset\_topic](#input\_offset\_topic) | Kafka topic where the connector stores source offsets. | `string` | n/a | yes |
| <a name="input_pdb_name"></a> [pdb\_name](#input\_pdb\_name) | Oracle pluggable database name (database.pdb.name), for a multitenant (CDB) source. Empty (default) omits the property. Ignored for engine = "mariadb". | `string` | `""` | no |
| <a name="input_plugin_arns"></a> [plugin\_arns](#input\_plugin\_arns) | Custom plugin ARNs keyed by "<flavour>-<version>" (msk-connect-plugin.plugin\_arns). Used when plugin\_version is set to pin a specific version. | `map(string)` | `{}` | no |
| <a name="input_plugin_revisions"></a> [plugin\_revisions](#input\_plugin\_revisions) | Custom plugin revisions keyed by "<flavour>-<version>" (msk-connect-plugin.plugin\_revisions). Used with plugin\_version. | `map(number)` | `{}` | no |
| <a name="input_plugin_version"></a> [plugin\_version](#input\_plugin\_version) | Pin a specific plugin version for this connector's engine. Empty (default)<br/>uses the flavour's default from default\_plugin\_arns; a non-empty value<br/>selects "<engine>-<version>" from plugin\_arns. Changing the resolved plugin<br/>forces connector replacement. See README for the default-vs-pinned selection. | `string` | `""` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | n/a | yes |
| <a name="input_schema_history_topic"></a> [schema\_history\_topic](#input\_schema\_history\_topic) | Kafka topic where Debezium stores captured schema history. | `string` | n/a | yes |
| <a name="input_server_id"></a> [server\_id](#input\_server\_id) | Debezium database.server.id. Must be stable per connector and unique<br/>across connectors. Leave null to derive it deterministically from<br/>identifier (see README for the derivation). | `string` | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the connector ENIs. Must reach the database and the Kafka brokers (from VPC project output). | `list(string)` | n/a | yes |
| <a name="input_tables"></a> [tables](#input\_tables) | JSON list of fully-qualified tables to capture. Locals join it into the<br/>module's table\_include\_list; an empty list ("[]") captures everything. | `string` | `"[]"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_topic_prefix"></a> [topic\_prefix](#input\_topic\_prefix) | Debezium topic prefix. Effectively immutable: changing it orphans existing topics. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the connector security group is created (from VPC project output). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_connector_arn"></a> [connector\_arn](#output\_connector\_arn) | ARN of the MSK Connect Debezium connector. |
| <a name="output_connector_name"></a> [connector\_name](#output\_connector\_name) | Name of the MSK Connect connector. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the security group attached to the connector's ENIs. |
| <a name="output_server_id"></a> [server\_id](#output\_server\_id) | Debezium database.server.id in effect (supplied or derived from identifier). |
| <a name="output_service_execution_role_arn"></a> [service\_execution\_role\_arn](#output\_service\_execution\_role\_arn) | ARN of the connector's service execution role. |
<!-- END_TF_DOCS -->