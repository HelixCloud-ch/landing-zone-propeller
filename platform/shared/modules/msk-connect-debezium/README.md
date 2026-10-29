# msk-connect-debezium

Shared Terraform module that stands up a single Debezium change-data-capture
connector on Amazon MSK Connect. It creates the connector and, optionally, its
security group, service execution IAM role and scoped policy, CloudWatch log
group, MSK Connect worker configuration and not-in-running-state CloudWatch
alarm; each of these can be supplied from elsewhere instead (see
[Bring your own resources](#bring-your-own-resources)). The connector configuration is built
from three merged layers (see [Connector configuration](#connector-configuration));
`mariadb` and `oracle` are supported; **Oracle is unverified against real
infrastructure**, see [Oracle](#oracle) below. The module takes plain AWS inputs — IDs, ARNs,
hostnames, topic names — and knows nothing about propeller's input shapes, so it
is usable on its own as well as through the
`platform/projects/msk-connect-debezium` project that adapts propeller
conventions onto it.

## Which runner and why

A consumer wiring this module into a pipeline must run it on the **Egress
Runner** when the module creates the service execution role: IAM is a global
service the in-VPC runner cannot reach; only the egress runner can. This is a
property of the resources the module creates, so it holds for any consumer, not
just the project. With an external role (`service_execution_role_arn`) no IAM
call is made, but the runner still needs to reach the MSK Connect API (and
CloudWatch Logs / EC2 for whatever else the module creates).

## Connector immutability and replace-on-plugin-change

MSK Connect connectors are immutable with respect to their plugin. Changing
`custom_plugin_arn` — which happens on a Debezium version bump — therefore
**replaces** the connector rather than updating it in place. The connector sets
`create_before_destroy` so the new connector is created before the old one is
removed, but a replacement still implies a CDC gap: while the old connector is
torn down and the new one starts and re-establishes its position, no changes are
captured. If the offset topic is lost or unreadable across the bump, the new
connector cannot resume from the recorded position and performs a full
re-snapshot of the source. Treat a plugin bump as an operational
event, not a routine apply.

## Bring your own resources

Only the connector itself is always created. Every supporting resource can be
managed elsewhere (a central networking, logging or IAM team, another stack):

| Resource | Input | Default | When the module does not create it |
| -------- | ----- | ------- | ---------------------------------- |
| Security group + egress rules | `create_security_group` | `true` | Supply `security_group_ids` (at least one SG overall). `vpc_id` and `additional_egress_rules` are only used with the created SG; `additional_egress_rules` is rejected without it. |
| Service execution role + policies | `service_execution_role_arn` | `null` (create) | No role, no policies, no KMS key lookup. `additional_policy_json` / `additional_policy_arns` are rejected; apply the `required_policy_json` output to the role instead (see [External service execution role](#external-service-execution-role)). |
| Worker configuration | `worker_configuration_arn` + `worker_configuration_revision` | `null` (create) | Both must be set together. `worker_config_overrides` is rejected and `offset_topic` is not needed. The external worker configuration must declare the offset topic and, if derived credentials are used, register the `ssm` config provider. |
| CloudWatch log group | `create_log_group` | `false` | Point `log_delivery` at an existing destination, or deliver no logs (see [Log delivery](#log-delivery)). |
| Not-running alarm | `create_alarm` | `false` | No alarm; `alarm_actions` is rejected. |

Outputs of resources the module does not create (`security_group_id`,
`log_group_name`, `worker_configuration_arn`, `alarm_arn`) are `null`;
`service_execution_role_arn` always returns the role in effect. Changing the
security group set, the worker configuration or the log delivery replaces the
connector (`UpdateConnector` covers only capacity and connector configuration).

### External service execution role

The role must trust MSK Connect, with the same confused-deputy conditions the
module puts on the role it creates:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "kafkaconnect.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": { "aws:SourceAccount": "<account-id>" },
        "ArnLike": { "aws:SourceArn": "arn:<partition>:kafkaconnect:<region>:<account-id>:connector/<connector-name>/*" }
      }
    }
  ]
}
```

The `SourceArn` wildcard is scoped to the connector name because the connector
ARN carries a random suffix generated at create time.

Its permissions are the `required_policy_json` output: the exact document the
module would attach (credential parameters, KMS, Kafka IAM). It is computed
even with an external role, so the role owners can apply it; it is `null` when
nothing needs granting. Two differences from a module-created role: with an
alias or key id in `cdc_kms_key_id` no lookup is done and the KMS statement is
left out (grant `kms:Decrypt` on the real key ARN yourself, or pass the key
ARN), and with `client_authentication = "IAM"` but no `kafka_cluster_arn` the
Kafka statements are left out.

The deploy role needs `iam:PassRole` on the external role, ideally with the
condition `iam:PassedToService = kafkaconnect.amazonaws.com`. See
[Understand service execution role](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-service-execution-role.html),
[Prevent cross-service confused deputy problem](https://docs.aws.amazon.com/msk/latest/developerguide/cross-service-confused-deputy-prevention.html)
and [Example of IAM policy for MSK Connect](https://docs.aws.amazon.com/msk/latest/developerguide/mkc-iam-policy-examples.html).

## Security group

The connector's ENIs live in `subnet_ids`, which must reach both the source
database (`db_port`) and the Kafka brokers (`broker_port`). The created
security group opens exactly those two egress ports; ingress is not needed
because the connector only initiates outbound connections.

When overrides make the connector reach something else (VPC endpoints for
Secrets Manager or S3, a second broker listener), add rules with
`additional_egress_rules`: a map keyed by a stable name (so state addresses
survive reordering), each entry with exactly one destination (`cidr_ipv4`,
`cidr_ipv6`, `prefix_list_id` or `referenced_security_group_id`). `to_port`
defaults to `from_port`; `ip_protocol = "-1"` drops both ports.
`security_group_ids` attaches existing security groups to the connector ENIs,
in addition to the created one or, with `create_security_group = false`,
instead of it; changing that set replaces the connector.

## Service execution role and policy

When the module creates the role, it is assumed by `kafkaconnect.amazonaws.com`
and is constrained by two confused-deputy conditions: `aws:SourceAccount` pins
the calling account, and `aws:SourceArn` pins connectors of this name in this
account and region. The connector ARN carries a random suffix generated at
create time and so cannot be pinned exactly, which is why the `SourceArn`
condition uses a name-scoped wildcard; `SourceAccount` still provides the
confused-deputy protection.

The attached policy grants `ssm:GetParameter` on **exactly** the two credential
parameter ARNs passed in, and nothing wider (no statement when the credentials
are not derived, see below). Kafka data-plane permissions depend
on `client_authentication`: with `NONE` the connector authenticates at the
transport layer and the policy grants **no** `kafka-cluster:*` permissions; with
`IAM` the policy adds cluster-level actions (`Connect`, `AlterCluster`,
`DescribeCluster`) plus topic and group actions, each scoped to the target
cluster's ARN and its derived topic/group ARNs. `kafka_cluster_arn` is therefore
required only for `IAM` with a module-created role. When no statement applies
the inline policy is not created (IAM rejects an empty policy document).

Overrides can reference resources the module knows nothing about (another SSM
parameter, a Secrets Manager secret, an S3 object). Grant them with
`additional_policy_json` (attached inline as `<identifier>-connector-additional`)
and/or `additional_policy_arns` (managed policy attachments; the ARNs must be
known at plan time because they key a `for_each`). The connector `depends_on`
every role policy and attachment, so the grants exist before it starts.

## Worker configuration and the SSM Config Provider

The worker configuration declares the offset topic and registers the AWS SSM
parameter-store Config Provider under the alias `ssm`. The connector config
(the derived layer) references the CDC credentials as
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

**The derived credentials are optional.** Leave `cdc_username_parameter` and
`cdc_password_parameter` (and their ARNs) all `null` and the module derives no
`database.user` / `database.password`, grants no `ssm:GetParameter` and does no
KMS lookup. Supply the credentials through `connector_config_overrides`
instead (for example `${secretsmanager:<secret>:username}` with the Secrets
Manager provider registered in the worker configuration) and grant read
access with `additional_policy_json` / `additional_policy_arns`, or on the
external role. The names and ARNs must be set together or not at all.

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

## Connector configuration

`connector_configuration` is the merge of three layers; a later layer wins on
the same key:

| Layer | Source | Keys |
| ----- | ------ | ---- |
| 1. Defaults | per engine, in `locals.tf` | `include.schema.changes=false`, `schema.history.internal.store.only.captured.tables.ddl=true`, `schema.history.internal.store.only.captured.databases.ddl=true`, `snapshot.mode=initial`; Oracle also `log.mining.strategy` (from `log_mining_strategy`) |
| 2. Derived | typed inputs | `connector.class`, `tasks.max=1`, `database.hostname`, `database.port`, `database.user` / `database.password` (`${ssm::<name>}`, when the credential parameters are set), `topic.prefix`, `schema.history.internal.kafka.bootstrap.servers`, `schema.history.internal.kafka.topic`, `config.action.reload=none`, `table.include.list` (when set); MariaDB `database.server.id`; Oracle `database.dbname`, `database.pdb.name` (when set); the [schema-history authentication](#schema-history-authentication) keys |
| 3. Overrides | `connector_config_overrides` | anything |

Typed inputs exist only for values Terraform itself needs outside the map
(security group ports, IAM scoping, the topic contract with `cdc-topics`, the
cluster authentication). Every other Debezium property (snapshot behaviour,
include lists, SMTs, converters, LogMiner tuning) goes through the defaults or
the overrides.

**A `null` removes the key.** Any key whose final value is `null` is dropped
from the map, so Debezium falls back to its own default. For example
`"include.schema.changes" = null` removes the module's opinionated `false`.

**Overrides are unrestricted.** There is no reserved-key list and no
validation: an override can replace any derived key, including
`database.user` / `database.password`, `connector.class` and the
schema-history authentication (useful when MSK Connect targets a
self-managed Kafka cluster). The module is no safety net. A plaintext secret
in the overrides is stored in Terraform state and the plan, and
`DescribeConnector` returns it. Prefer `${ssm::<name>}` or
`${secretsmanager:<secret>:<key>}` placeholders and grant read access with
`additional_policy_json` / `additional_policy_arns`. The merged map is
exported as the sensitive `connector_configuration` output.

**Updates.** `UpdateConnector` accepts only capacity and connector
configuration ([UpdateConnector](https://docs.aws.amazon.com/MSKC/latest/mskc/API_UpdateConnector.html)),
so override and `mcu_count` changes update the connector in place, while
security group, worker-configuration and log-delivery changes replace it.

**Escaping `${...}`.** Kafka Connect placeholders use the same `${` as
Terraform templates. In HCL (`.tf`, `.tfvars`) write `$${...}`
(`"<prefix>.v1.$${routedByValue}"`, `"$${ssm::/path}"`), see
[String templates](https://developer.hashicorp.com/terraform/language/expressions/strings).
In JSON (`.tfvars.json`, propeller pipeline literals) write `${...}` as is:
Terraform does not interpolate string values in JSON variable files.
`${routedByValue}` has no `:`, so the config providers leave it alone and the
outbox router resolves it.

### Schema-history authentication

Debezium's schema-history producer and consumer are plain Kafka clients and do
not inherit MSK Connect's cluster authentication. The module derives their
settings from `client_authentication` and `in_transit_encryption`, for both
the `schema.history.internal.producer.` and `schema.history.internal.consumer.`
prefixes:

| Cluster access | Derived keys (per prefix) |
| -------------- | ------------------------- |
| `IAM` | `security.protocol=SASL_SSL`, `sasl.mechanism=AWS_MSK_IAM`, `sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;`, `sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler` |
| `NONE` + `TLS` | `security.protocol=SSL` |
| `NONE` + `PLAINTEXT` | none (the Kafka client default is `PLAINTEXT`) |

The IAM keys are the ones AWS uses in
[Create a Debezium source connector](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-debeziumsource-connector-example-steps.html).
The plugin artifact does not bundle the
[aws-msk-iam-auth](https://github.com/aws/aws-msk-iam-auth) jar. AWS's own
example builds its plugin from the Debezium connector and a config provider
only, which implies the MSK Connect runtime provides the IAM login module;
this has not been verified against a live connector. If an IAM connector fails
with `ClassNotFoundException: software.amazon.msk.auth.iam.IAMLoginModule`,
add the jar to the plugin artifact build. See also
[Configure clients for IAM access control](https://docs.aws.amazon.com/msk/latest/developerguide/configure-clients-for-iam-access-control.html).

### Worker configuration overrides

The worker configuration defaults are `key.converter` (`StringConverter`),
`value.converter` (`JsonConverter`), `value.converter.schemas.enable=false`,
`offset.storage.topic`, and the `ssm` config provider (`config.providers`,
`config.providers.ssm.class`, `config.providers.ssm.param.region`).
`worker_config_overrides` merges over them with the same null-removes
semantics and is rendered as sorted `key=value` lines. Worker configurations
cannot be updated in place, so the resource name carries a hash of the
content: any change creates a new worker configuration and replaces the
connector. Example adding the Secrets Manager provider from
[msk-config-providers](https://github.com/aws-samples/msk-config-providers):

```hcl
worker_config_overrides = {
  "config.providers"                             = "ssm,secretsmanager"
  "config.providers.secretsmanager.class"        = "com.amazonaws.kafka.config.providers.SecretsManagerConfigProvider"
  "config.providers.secretsmanager.param.region" = "<region>"
}
```

### Example: Oracle with the outbox pattern

Placeholders only; HCL form (note `$${`):

```hcl
engine              = "oracle"
db_port             = 1521
db_name             = "<SERVICE_NAME>"
log_mining_strategy = "online_catalog"
table_include_list  = "<SCHEMA>.OUTBOX_EVENT" # project: tables = ["<SCHEMA>.OUTBOX_EVENT"]

connector_config_overrides = {
  "database.url"                                         = "jdbc:oracle:thin:@//<db-host>:1521/<SERVICE_NAME>"
  "database.connection.adapter"                          = "logminer"
  "lob.enabled"                                          = "true"
  "log.mining.sleep.time.min.ms"                         = "<ms>"
  "log.mining.sleep.time.max.ms"                         = "<ms>"
  "log.mining.sleep.time.default.ms"                     = "<ms>"
  "log.mining.scn.gap.detection.gap.size.min"            = "<scn-gap>"
  "log.mining.scn.gap.detection.time.interval.max.ms"    = "<ms>"
  "log.mining.archive.log.only.mode"                     = "false"
  "snapshot.locking.mode"                                = "none"
  "snapshot.select.statement.overrides"                  = "<SCHEMA>.<TABLE>"
  "snapshot.select.statement.overrides.<SCHEMA>.<TABLE>" = "SELECT * FROM <SCHEMA>.<TABLE> WHERE <condition>"
  "poll.interval.ms"                                     = "5000"
  "max.batch.size"                                       = "1024"
  "key.converter"                                        = "org.apache.kafka.connect.storage.StringConverter"
  "value.converter"                                      = "org.apache.kafka.connect.json.JsonConverter"
  "value.converter.schemas.enable"                       = "false"
  "transforms"                                           = "outbox"
  "transforms.outbox.type"                               = "io.debezium.transforms.outbox.EventRouter"
  "transforms.outbox.table.field.event.id"               = "<ID_COLUMN>"
  "transforms.outbox.table.field.event.key"              = "<KEY_COLUMN>"
  "transforms.outbox.table.field.event.payload"          = "<PAYLOAD_COLUMN>"
  "transforms.outbox.table.fields.additional.placement"  = "<TYPE_COLUMN>:header:eventType"
  "transforms.outbox.route.by.field"                     = "<ROUTE_COLUMN>"
  "transforms.outbox.route.topic.replacement"            = "<prefix>.v1.$${routedByValue}"
  "transforms.outbox.table.expand.json.payload"          = "true"
  "transforms.outbox.table.json.payload.null.behavior"   = "optional_bytes"
}
```

- `snapshot.mode=initial` and `include.schema.changes=false` are already
  defaults and are omitted.
- Debezium still requires `database.dbname` alongside `database.url`.
- The routed topics (`<prefix>.v1.<value>`) must be created by `cdc-topics`:
  MSK defaults `auto.create.topics.enable` to `false`.
- `table.fields.additional.placement` puts the event type column in a
  message header (`column:header|envelope[:alias]`); drop it if consumers do
  not need the type.
- See the [outbox event router](https://debezium.io/documentation/reference/2.7/transformations/outbox-event-router.html)
  and the [Oracle connector](https://debezium.io/documentation/reference/2.7/connectors/oracle.html)
  property references. Links target 2.7, the plugin version in the
  `msk-connect-plugin` example; use the docs of the plugin version you
  register (see [Debezium versions](#debezium-versions)).

### Example: MariaDB

```hcl
engine = "mariadb"

connector_config_overrides = {
  "snapshot.mode"                                = "recovery"
  "database.include.list"                        = "<database>"
  "table.include.list"                           = "<database>\\.(<table_a>|<table_b>)"
  "schema.history.internal.skip.unparseable.ddl" = "true"
}
```

A regex `table.include.list` in the overrides wins over the derived one.
Property reference: [MariaDB connector](https://debezium.io/documentation/reference/2.7/connectors/mariadb.html).

### Kafka Connect keys that do not port to MSK Connect

Keys commonly found in self-managed Kafka Connect configurations that have no
effect, or no equivalent, on MSK Connect:

- `producer.override.ssl.*` and `schema.history.internal.{producer,consumer}.ssl.*`
  keystore/truststore settings: these implement mTLS client authentication,
  and MSK Connect client authentication is only `NONE` or `IAM`
  ([KafkaClusterClientAuthentication](https://docs.aws.amazon.com/MSKC/latest/mskc/API_KafkaClusterClientAuthentication.html)).
- `${dir:...}` / `${env:...}` placeholders: only the config providers declared
  in the worker configuration exist.
- `name`: MSK Connect sets it from the connector name.
- `database.server.id` on Oracle: unused by the Oracle connector.
- OpenLineage noop settings.
- Prefixed `schema.history.internal.{producer,consumer}.store.only.captured.*`:
  no-ops; only the unprefixed `schema.history.internal.store.only.captured.*`
  keys matter (already defaults).
- `transforms.outbox.route.key.field`, `transforms.outbox.table.field.event.type`
  and `value.converter.json.write.null.properties`: not options of the outbox
  event router (2.7 and 3.x docs) or of Kafka's `JsonConverter` (3.7 and
  trunk), so Kafka Connect ignores them on any runtime, Strimzi included.
  Carry the event type column with `table.fields.additional.placement` (see
  the Oracle example).

A Kafka cluster that requires mTLS client authentication (for example Strimzi
with TLS client auth) cannot be targeted by MSK Connect; overrides cannot fix
this.

## Connector

Provisioned capacity with one worker; `mcu_count` (1, 2, 4 or 8, see
[ProvisionedCapacity](https://docs.aws.amazon.com/MSKC/latest/mskc/API_ProvisionedCapacity.html))
sizes it. `worker_count` stays 1 because Debezium runs a single task. The
API's `networkType` (`IPV4` | `DUAL`,
[CreateConnector](https://docs.aws.amazon.com/MSKC/latest/mskc/API_CreateConnector.html))
is not exposed: the AWS provider `~> 6.0` (checked at 6.70.0) has no
`network_type` argument on `aws_mskconnect_connector`. `client_authentication` (`NONE` | `IAM`)
and `in_transit_encryption` (`PLAINTEXT` | `TLS`) are independent inputs with no
built-in assumption about which combination a cluster uses — a consumer sets both
to match its cluster. `server_id` (Debezium `database.server.id`) is derived
deterministically per connector by the caller so it is stable across applies and
distinct across connectors. `topic_prefix` is effectively immutable: changing it
orphans the existing topics and breaks schema-history recovery, so it should be
treated as fixed for the life of the connector.

## Debezium versions

The module pins no Debezium version; the registered plugin decides it. The
constraint is the MSK Connect runtime: Kafka Connect 2.7.1 runs on Java 11 and
3.7.x on Java 17
([custom plugins](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-plugins.html)).
Debezium 3.x connectors require Java 17+ and Kafka Connect 3.1 or later
([tested versions](https://debezium.io/releases/)), so a 3.x plugin needs
`kafkaconnect_version = "3.7.x"` (the default). Whatever Kafka Connect version
a consumer runs elsewhere, on MSK Connect the connector runs on 3.7.x.
Moving from 2.7 to 3.x renames or removes some connector options; check an
existing configuration against the docs of the target series before switching
plugins.

## Oracle

> **Unverified against real infrastructure.** The Oracle configuration is
> written and offline-tested (rendering only — no connector has ever been
> deployed against a live Oracle source); verify it before production use. See
> [`cdc-prepare-oracle`](../../../projects/cdc-prepare-oracle/README.md) for the
> database-side preparation this connector depends on.

`engine = "oracle"` selects
`connector.class=io.debezium.connector.oracle.OracleConnector` and the Oracle
entries of the defaults and derived layers, driven by three inputs MariaDB
does not use:

- **`db_name`** — the Oracle service name / SID (`database.dbname`). On a CDB
  instance this is the container database's service.
- **`pdb_name`** — the pluggable database name (`database.pdb.name`), for a
  multitenant (CDB) source. Empty (default) omits the property entirely,
  because a non-CDB instance has no PDB to name — the same
  omit-rather-than-emit-empty convention `table_include_list` already uses.
- **`log_mining_strategy`** — Oracle LogMiner's `log.mining.strategy`,
  defaulting to `hybrid`. It sets the defaults layer, so an override of
  `log.mining.strategy` wins over it.

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
impact on the source is already the primary open risk.

### A known open risk

The community has reported `ORA-01031` (insufficient privileges) against RDS
for Oracle **CDB** instances specifically, even with every grant
`cdc-prepare-oracle` issues in place, because the root-container-level
privileges Debezium's connector needs cannot always be granted the same way
on RDS as on a self-managed Oracle instance. This has not been resolved or
tested against a real RDS for Oracle CDB instance; close it before production
use.

## Log delivery

> **Without log delivery a failing connector is very hard to debug.** MSK
> Connect keeps no worker logs of its own: a connector stuck in `CREATING` or
> `FAILED` shows no reason beyond its state. Enable at least one destination
> for anything beyond a throwaway test.

`log_delivery` (default `null`, no worker logs) selects one or more of the
three destinations MSK Connect supports
([Logging for MSK Connect](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-logging.html)):

```hcl
log_delivery = {
  cloudwatch_logs = { log_group = "<existing-log-group>" } # or {} with create_log_group = true
  s3              = { bucket = "<bucket>", prefix = "<prefix>" } # prefix optional
  firehose        = { delivery_stream = "<delivery-stream>" }
}
```

Set only the destinations you want; a non-null `log_delivery` must set at
least one. `create_log_group = true` creates `/aws/mskconnect/<identifier>`
with a finite, overridable retention (`log_retention_in_days`, default 30) and
requires `cloudwatch_logs = {}` (no `log_group`: the created group is used).
Changing `log_delivery` replaces the connector.

### Permissions on the deploy role (not the connector role)

MSK Connect worker logs are vended logs that need additional permissions on
the principal that **creates the connector**, i.e. the role Terraform runs
with, not the service execution role
([Logging that requires additional permissions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AWS-vended-logs-permissions.html),
[supported destinations](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AWS-logs-destinations-table.html)):

- **CloudWatch Logs**: `logs:CreateLogDelivery`, `logs:PutResourcePolicy`,
  `logs:DescribeResourcePolicies`, `logs:DescribeLogGroups` (the last three on
  `arn:<partition>:logs:<region>:<account-id>:log-group:*`). AWS adds a
  resource policy for `delivery.logs.amazonaws.com` to the log group (51,200
  byte limit, shared by all deliveries)
  ([Logs sent to CloudWatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AWS-logs-infrastructure-CWL.html)).
- **S3**: `logs:CreateLogDelivery`, `s3:GetBucketPolicy`, `s3:PutBucketPolicy`
  on the bucket. AWS adds a bucket policy statement for
  `delivery.logs.amazonaws.com`; a bucket policy using `NotAction` or
  `NotPrincipal` needs that statement added by hand, and SSE-KMS with a
  customer-managed key needs a key-policy grant for the delivery service
  ([Logs sent to Amazon S3](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AWS-logs-infrastructure-S3.html)).
- **Firehose**: `logs:CreateLogDelivery`, `firehose:TagDeliveryStream`, and
  `iam:CreateServiceLinkedRole` the first time (it creates
  `AWSServiceRoleForLogDelivery`)
  ([Logs sent to Firehose](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AWS-logs-infrastructure-Firehose.html)).

`logs:GetLogDelivery`, `logs:ListLogDeliveries` and `logs:DeleteLogDelivery`
are not listed by those pages but are likely needed when a connector with log
delivery is replaced or deleted; verify them at the first deploy.

## Alarm

`create_alarm` (default `false`) creates a CloudWatch alarm that fires when the
connector's running task count drops below one. `alarm_actions` (for example
SNS topic ARNs) are accepted only together with `create_alarm`, because
notification targets are consumer-specific. Note that the alarm fires for the
whole duration of any sleep window, since a slept connector is not running.

## Accepted checkov findings

Two findings on the optional log group are accepted with justification (see
the inline `checkov:skip` comments), not fixed:

- **Log group retention (CKV_AWS_338).** Retention is a deliberate, finite,
  consumer-overridable input (`log_retention_in_days`) rather than an enforced
  one-year minimum: connector logs carry operational status, not audit data.
- **Log group KMS encryption (CKV_AWS_158).** Connector logs carry operational
  status, not captured row data (that flows to Kafka topics), and CloudWatch
  Logs encrypts log data at rest by default. A customer-managed key would need
  a new key input plus a key-policy grant for the logs service; a consumer that
  needs one can bring its own log group through `log_delivery`.

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
- [Create a Debezium source connector (MSK Connect)](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-debeziumsource-connector-example-steps.html) — schema-history IAM keys.
- [Prevent cross-service confused deputy problem (MSK)](https://docs.aws.amazon.com/msk/latest/developerguide/cross-service-confused-deputy-prevention.html)
- [Example of IAM policy for MSK Connect](https://docs.aws.amazon.com/msk/latest/developerguide/mkc-iam-policy-examples.html) — `iam:PassRole` for the deploy role.
- [Logging for MSK Connect](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-logging.html)
- [Logging that requires additional permissions (vended logs)](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AWS-vended-logs-permissions.html)
- [MSK Connect API: UpdateConnector](https://docs.aws.amazon.com/MSKC/latest/mskc/API_UpdateConnector.html)
- [MSK Connect API: ProvisionedCapacity](https://docs.aws.amazon.com/MSKC/latest/mskc/API_ProvisionedCapacity.html)
- [Debezium connector for MariaDB (2.7)](https://debezium.io/documentation/reference/2.7/connectors/mariadb.html)
- [Debezium connector for Oracle (2.7)](https://debezium.io/documentation/reference/2.7/connectors/oracle.html) — `log.mining.strategy` options.
- [Debezium outbox event router (2.7)](https://debezium.io/documentation/reference/2.7/transformations/outbox-event-router.html)
- [aws-msk-iam-auth](https://github.com/aws/aws-msk-iam-auth)
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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.70.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.connector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.not_running](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_role.connector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.connector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_mskconnect_connector.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mskconnect_connector) | resource |
| [aws_mskconnect_worker_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mskconnect_worker_configuration) | resource |
| [aws_security_group.connector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
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
| <a name="input_additional_egress_rules"></a> [additional\_egress\_rules](#input\_additional\_egress\_rules) | Extra egress rules on the created security group, keyed by a stable name.<br/>Each sets exactly one destination; to\_port defaults to from\_port. | <pre>map(object({<br/>    from_port                    = number<br/>    to_port                      = optional(number)<br/>    ip_protocol                  = optional(string, "tcp")<br/>    cidr_ipv4                    = optional(string)<br/>    cidr_ipv6                    = optional(string)<br/>    prefix_list_id               = optional(string)<br/>    referenced_security_group_id = optional(string)<br/>    description                  = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_additional_policy_arns"></a> [additional\_policy\_arns](#input\_additional\_policy\_arns) | Managed policy ARNs (known at plan time) for the created role. Not allowed with an external role. | `list(string)` | `[]` | no |
| <a name="input_additional_policy_json"></a> [additional\_policy\_json](#input\_additional\_policy\_json) | Extra IAM policy document (JSON) attached inline to the created role, for<br/>resources that overrides reference. Not allowed with an external role. | `string` | `null` | no |
| <a name="input_alarm_actions"></a> [alarm\_actions](#input\_alarm\_actions) | Actions for the not-running alarm (e.g. SNS topic ARNs). Only with create\_alarm. | `list(string)` | `[]` | no |
| <a name="input_bootstrap_servers"></a> [bootstrap\_servers](#input\_bootstrap\_servers) | Kafka bootstrap servers string the connector and the schema-history writer connect to. | `string` | n/a | yes |
| <a name="input_broker_port"></a> [broker\_port](#input\_broker\_port) | Kafka broker port. Opened as egress on the created security group. | `number` | `9098` | no |
| <a name="input_cdc_kms_key_id"></a> [cdc\_kms\_key\_id](#input\_cdc\_kms\_key\_id) | KMS key (alias, id or ARN) encrypting the CDC SecureString parameters.<br/>alias/aws/ssm (default) adds no kms:Decrypt. Ignored when credentials are<br/>null. See README. | `string` | `"alias/aws/ssm"` | no |
| <a name="input_cdc_password_parameter"></a> [cdc\_password\_parameter](#input\_cdc\_password\_parameter) | SSM parameter holding the CDC user password. Set or null together with the username. | `string` | `null` | no |
| <a name="input_cdc_password_parameter_arn"></a> [cdc\_password\_parameter\_arn](#input\_cdc\_password\_parameter\_arn) | ARN of cdc\_password\_parameter; scopes ssm:GetParameter. Set exactly when the name is set. | `string` | `null` | no |
| <a name="input_cdc_username_parameter"></a> [cdc\_username\_parameter](#input\_cdc\_username\_parameter) | SSM parameter holding the CDC user name, referenced via the ssm config<br/>provider. Null (with the password) derives no credentials. See README. | `string` | `null` | no |
| <a name="input_cdc_username_parameter_arn"></a> [cdc\_username\_parameter\_arn](#input\_cdc\_username\_parameter\_arn) | ARN of cdc\_username\_parameter; scopes ssm:GetParameter. Set exactly when the name is set. | `string` | `null` | no |
| <a name="input_client_authentication"></a> [client\_authentication](#input\_client\_authentication) | MSK Connect client authentication. NONE grants no kafka-cluster permissions; IAM adds them. SASL/SCRAM is unavailable to a connector. | `string` | `"NONE"` | no |
| <a name="input_connector_config_overrides"></a> [connector\_config\_overrides](#input\_connector\_config\_overrides) | Connector properties merged last, over the module defaults and the<br/>derived values; a null value removes the key. Unrestricted: see README. | `map(string)` | `{}` | no |
| <a name="input_create_alarm"></a> [create\_alarm](#input\_create\_alarm) | Create the connector not-running CloudWatch alarm. | `bool` | `false` | no |
| <a name="input_create_log_group"></a> [create\_log\_group](#input\_create\_log\_group) | Create the /aws/mskconnect/<identifier> log group and deliver to it.<br/>Requires log\_delivery.cloudwatch\_logs without log\_group. See README. | `bool` | `false` | no |
| <a name="input_create_security_group"></a> [create\_security\_group](#input\_create\_security\_group) | Create the connector security group (with database and broker egress rules). | `bool` | `true` | no |
| <a name="input_custom_plugin_arn"></a> [custom\_plugin\_arn](#input\_custom\_plugin\_arn) | ARN of the registered MSK Connect custom plugin. Changing it forces connector replacement (MSK Connect connectors are immutable wrt their plugin). | `string` | n/a | yes |
| <a name="input_custom_plugin_revision"></a> [custom\_plugin\_revision](#input\_custom\_plugin\_revision) | Revision of the custom plugin to pin. Defaults to 1, the revision an MSK Connect custom plugin is created with. | `number` | `1` | no |
| <a name="input_db_host"></a> [db\_host](#input\_db\_host) | Hostname of the source database the connector reads from. | `string` | n/a | yes |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Oracle service name / SID (database.dbname). Ignored for mariadb.<br/>On a CDB source this is the container's service; see pdb\_name. | `string` | `""` | no |
| <a name="input_db_port"></a> [db\_port](#input\_db\_port) | Port of the source database. Opened as egress on the created security group. | `number` | `3306` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | Source engine. Selects the connector class and the per-engine defaults. | `string` | `"mariadb"` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Unique connector identifier. Names all associated resources and seeds the deterministic Debezium server id. | `string` | n/a | yes |
| <a name="input_in_transit_encryption"></a> [in\_transit\_encryption](#input\_in\_transit\_encryption) | Encryption in transit to the cluster: PLAINTEXT or TLS. Independent of client\_authentication, with no built-in assumption. | `string` | `"PLAINTEXT"` | no |
| <a name="input_kafka_cluster_arn"></a> [kafka\_cluster\_arn](#input\_kafka\_cluster\_arn) | ARN of the target MSK cluster; scopes the kafka-cluster:* grants. Required<br/>only for IAM auth when the module creates the role. | `string` | `null` | no |
| <a name="input_kafkaconnect_version"></a> [kafkaconnect\_version](#input\_kafkaconnect\_version) | Kafka Connect version for the connector. MSK Connect supports 2.7.1 and 3.7.x only. | `string` | `"3.7.x"` | no |
| <a name="input_log_delivery"></a> [log\_delivery](#input\_log\_delivery) | Worker log destinations (cloudwatch\_logs, s3, firehose). Null (default)<br/>delivers no logs, which makes failures very hard to debug. See README. | <pre>object({<br/>    cloudwatch_logs = optional(object({<br/>      log_group = optional(string)<br/>    }))<br/>    s3 = optional(object({<br/>      bucket = string<br/>      prefix = optional(string)<br/>    }))<br/>    firehose = optional(object({<br/>      delivery_stream = string<br/>    }))<br/>  })</pre> | `null` | no |
| <a name="input_log_mining_strategy"></a> [log\_mining\_strategy](#input\_log\_mining\_strategy) | Oracle log.mining.strategy, set in the defaults layer (overridable).<br/>Ignored for mariadb. See README for hybrid vs online\_catalog. | `string` | `"hybrid"` | no |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | Retention for the created log group (used only with create\_log\_group). | `number` | `30` | no |
| <a name="input_mcu_count"></a> [mcu\_count](#input\_mcu\_count) | MCUs per worker (1, 2, 4 or 8). worker\_count stays 1: Debezium runs a single task. | `number` | `1` | no |
| <a name="input_offset_topic"></a> [offset\_topic](#input\_offset\_topic) | Kafka topic for source offsets, declared in the created worker<br/>configuration. Required unless worker\_configuration\_arn is set. | `string` | `null` | no |
| <a name="input_pdb_name"></a> [pdb\_name](#input\_pdb\_name) | Oracle pluggable database (database.pdb.name) for a CDB source.<br/>Empty (default) omits the property. Ignored for mariadb. | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region as a literal, used for the ssm config provider in the created worker configuration. | `string` | n/a | yes |
| <a name="input_schema_history_topic"></a> [schema\_history\_topic](#input\_schema\_history\_topic) | Kafka topic where Debezium stores captured schema history. | `string` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Existing security groups for the connector ENIs, added to the created one<br/>(if any). At least one SG overall. Changing the set replaces the connector. | `list(string)` | `[]` | no |
| <a name="input_server_id"></a> [server\_id](#input\_server\_id) | Debezium database.server.id. Must be stable per connector and unique across connectors; the project derives it deterministically from identifier. | `string` | n/a | yes |
| <a name="input_service_execution_role_arn"></a> [service\_execution\_role\_arn](#input\_service\_execution\_role\_arn) | Existing service execution role for the connector. When set, the module<br/>creates no role or policies; apply required\_policy\_json to it. See README. | `string` | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs the connector's ENIs are placed in. Must reach the database and the Kafka brokers. | `list(string)` | n/a | yes |
| <a name="input_table_include_list"></a> [table\_include\_list](#input\_table\_include\_list) | Comma-separated table.include.list. Empty (default) omits the property and captures everything. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to resources that take a tags map. The project passes the merged tag set; the module does not know propeller's tag triple. | `map(string)` | `{}` | no |
| <a name="input_topic_prefix"></a> [topic\_prefix](#input\_topic\_prefix) | Debezium topic prefix. Effectively immutable: changing it orphans existing topics and breaks schema-history recovery. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for the created security group. Required only when create\_security\_group is true. | `string` | `null` | no |
| <a name="input_worker_config_overrides"></a> [worker\_config\_overrides](#input\_worker\_config\_overrides) | Worker properties merged over the module defaults; null removes a key. See README. | `map(string)` | `{}` | no |
| <a name="input_worker_configuration_arn"></a> [worker\_configuration\_arn](#input\_worker\_configuration\_arn) | Existing MSK Connect worker configuration to use instead of creating one. See README. | `string` | `null` | no |
| <a name="input_worker_configuration_revision"></a> [worker\_configuration\_revision](#input\_worker\_configuration\_revision) | Revision of worker\_configuration\_arn. Set both or neither. | `number` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alarm_arn"></a> [alarm\_arn](#output\_alarm\_arn) | ARN of the module-created not-running alarm; null when not created. |
| <a name="output_connector_arn"></a> [connector\_arn](#output\_connector\_arn) | ARN of the MSK Connect connector. The project re-exports this as its own Terraform output. |
| <a name="output_connector_configuration"></a> [connector\_configuration](#output\_connector\_configuration) | Final merged connector configuration. Sensitive: overrides are unrestricted and may hold plaintext secrets. |
| <a name="output_connector_name"></a> [connector\_name](#output\_connector\_name) | Name of the MSK Connect connector. |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Name of the module-created CloudWatch log group; null when not created. |
| <a name="output_required_policy_json"></a> [required\_policy\_json](#output\_required\_policy\_json) | Policy the service execution role needs (apply it to an external role). Null when no grant is needed. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the module-created connector security group; null when not created. |
| <a name="output_service_execution_role_arn"></a> [service\_execution\_role\_arn](#output\_service\_execution\_role\_arn) | ARN of the connector's service execution role in effect (created or supplied). |
| <a name="output_worker_configuration_arn"></a> [worker\_configuration\_arn](#output\_worker\_configuration\_arn) | ARN of the module-created worker configuration; null when not created. |
<!-- END_TF_DOCS -->
