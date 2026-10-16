# CDC Topics

Creates the Kafka topics a Debezium connector needs — the schema history topic,
the offset topic, and any others supplied as input — with per-topic partitions
and configuration. This is a non-Terraform, `just`-driven project with no
Terraform state.

Existing topics are left untouched and cluster-wide configuration is never
modified. The project only creates the topics it is asked to create; it makes no
assumption about which topics a given cluster needs, so the recommended settings
below are guidance, not defaults baked into the code.

## What it does

`apply` runs `topics.py`, which builds a `KafkaAdminClient` and creates each
requested topic with its partitions and configuration. An already-existing topic
is treated as success and its configuration is left unchanged — creating a topic
the cluster (or MSK Connect) would have created anyway is a no-op. Automatic
topic creation is never enabled and the cluster configuration is never altered.
`destroy` deletes nothing.

## Runner

Requires the **In_VPC_Runner**, because the Kafka brokers are private (in-VPC)
and unreachable from an egress runner. It connects to nothing outside the VPC,
so it needs no internet route.

The runner's deploy-runner image must carry `kafka-python` (the admin client)
and `aws-msk-iam-sasl-signer-python` (the IAM/OAUTHBEARER token provider used
against an IAM-authenticated cluster). Both are baked into the image by the
`deploy-runner-image` project; this project imports them offline.

## Pipeline wiring

`bootstrap_servers` comes from whichever project publishes the broker list;
`security_protocol` and the topics list come from the consumer's own CDC
configuration — this project takes no position on where that configuration
lives, only on the shape it must arrive in. Two ways to supply it:

**As a pipeline literal**, when another step's output is itself the topics
JSON (e.g. a `cdc-config` step assembled it from consumer settings):

```yaml
stages:
  - name: cdc-topics
    steps:
      - project: cdc-topics
        target: workload-account
        runner: in-vpc
        inputs:
          - name: msk-cluster.bootstrap_brokers_sasl_iam
            var: bootstrap_servers
          - name: cdc-config.security_protocol
            var: security_protocol
          - name: cdc-config.topics
            var: topics
```

**As a literal pinned in the pipeline itself**, when the topic list is fixed
for this consumer and does not come from another step's output:

```yaml
stages:
  - name: cdc-topics
    steps:
      - project: cdc-topics
        target: workload-account
        runner: in-vpc
        inputs:
          - name: msk-cluster.bootstrap_brokers_sasl_iam
            var: bootstrap_servers
          - var: security_protocol
            literal: "SASL_SSL"
          - var: topics
            literal: '[{"name":"schema-history.my-connector","partitions":1,"configs":{"cleanup.policy":"delete","retention.ms":"-1","retention.bytes":"-1"}}]'
```

A `literal` travels inside the pipeline bundle in cleartext (see
[`docs/pipeline-schema.md`](../../../docs/pipeline-schema.md)), which is fine
here — topic names and partition counts carry no secret.

**From a file checked into the consumer repo**, when the list is long enough
that inlining it as a JSON literal is unwieldy. A pipeline `literal` is just a
fixed value — it does not have to be the JSON itself, it can be a *path*:

```yaml
        inputs:
          - name: msk-cluster.bootstrap_brokers_sasl_iam
            var: bootstrap_servers
          - var: security_protocol
            literal: "SASL_SSL"
          - var: topics_file
            literal: "topics.json"
```

`topics_file` is resolved by `topics.py` at apply time, relative to this
project's own directory — so the file must be layered in via the project's
[overlay mechanism](../../../docs/pipeline-schema.md#overlays), the same way a
consumer overrides any other file that ships with a project. See
[Example configs](#example-configs) for ready-made files to copy in as the
overlay's `topics.json`.

See "Both cluster shapes" below for the two authentication forms.

## Inputs

Inputs arrive as `PROPELLER_INPUT_*` environment variables. Nothing about the
bootstrap servers, topic names, security protocol, account or region is
hardcoded.

| Input | Required | Meaning |
| ----- | :------: | ------- |
| `PROPELLER_INPUT_bootstrap_servers` | yes | Comma-separated Kafka broker list. Always supplied by the consumer. |
| `PROPELLER_INPUT_topics` | no | JSON list of `{name, partitions, configs}`, inline. `partitions` defaults to 1 and `configs` to `{}`. Mutually exclusive with `PROPELLER_INPUT_topics_file`. |
| `PROPELLER_INPUT_topics_file` | no | Path to a JSON file holding the same shape, relative to this project's directory. Use this instead of inlining a long list. Mutually exclusive with `PROPELLER_INPUT_topics`. See [Example configs](#example-configs). |
| `PROPELLER_INPUT_security_protocol` | yes | `PLAINTEXT` or `SASL_SSL`. **No default** — see below. |

Setting neither `topics` input creates nothing; setting both is an error (both
`plan` and `apply` report it, rather than silently picking one).

`AWS_REGION` (a standard runner environment variable, not a `PROPELLER_INPUT_*`)
is read only when `security_protocol` is `SASL_SSL`, to mint the IAM/OAUTHBEARER
token; a `PLAINTEXT` run ignores it.

### Why `security_protocol` has no default

`security_protocol` is required and deliberately has no default. Everywhere else
in the CDC projects an unknown is exposed as an input and defaulted to the option
whose failure mode is harmless — but here both wrong-guess directions carry cost.
Defaulting to `SASL_SSL` against a plaintext cluster fails to connect (loud, but
a false stop); defaulting to `PLAINTEXT` against a cluster that expects IAM+TLS
would attempt an unauthenticated, unencrypted connection — a silent security
regression on data that carries full row images. Because neither default is
harmless, the consumer must state the protocol explicitly.

## Recommended topic settings (guidance)

The values below are **recommendations for the consumer's `topics` input**, not
defaults hardcoded in the project — keeping the project generic. Pass them as
the `configs` map on each topic.

Recommend passing the **superset** of topics — schema history plus the three
Kafka Connect internal topics (offset, config, status). Kafka Connect in
distributed mode auto-creates its internal topics at worker startup, but whether
the *managed* MSK Connect wrapper pre-creates them with good settings, or relies
on first-start auto-creation with broker defaults, is unverified. Pre-creating a
topic MSK Connect would have created anyway is harmless (already-exists is
success); the harmful case is an auto-created offset/config/status topic that
lands with `cleanup.policy=delete` instead of `compact` and later drops the
connector's state. Passing the superset with correct settings picks the harmless
side of that asymmetry.

### Schema history topic

One partition, never more — the topic must keep a single global order of DDL.
`cleanup.policy=delete` (compaction would discard intermediate DDL and break
recovery) with infinite retention in both time and bytes, replicated to the
cluster's durability target.

| Setting | Value |
| ------- | ----- |
| `partitions` | `1` |
| `cleanup.policy` | `delete` |
| `retention.ms` | `-1` |
| `retention.bytes` | `-1` |
| replication factor | match the cluster's durability target (e.g. 3 on a 3-broker cluster) |

The single-partition requirement and the `retention.bytes=-1` fix are documented
by Debezium: the connector must keep a consistent global order in the schema
history topic ([Debezium connector for MariaDB — schema history topic (2.7)](https://debezium.io/documentation/reference/2.7/connectors/mariadb.html)),
and an unbounded byte retention prevents partial deletion that otherwise makes
the connector fail to recover after a restart
([A Note On Database History Topic Configuration](https://debezium.io/blog/2018/03/16/note-on-database-history-topic-configuration/)).
Debezium's own auto-create guidance uses `cleanup.policy=delete` for history-type
topics and reserves `compact` for keyed topics
([Auto-creating Debezium Change Data Topics](https://debezium.io/blog/2020/09/15/debezium-auto-create-topics/)).

### Offset topic (and config / status if pre-created)

The Kafka Connect worker state topics. `cleanup.policy=compact` — their state is
keyed and governed by compaction, never by a finite time or size retention.
Replicated. Do **not** set a finite `retention.ms` on these.

| Topic | `partitions` | `cleanup.policy` | replication factor |
| ----- | :----------: | ---------------- | ------------------ |
| offset (`connect-offsets`) | several (Connect default is high) | `compact` | replicated (≥3 in production) |
| config (`connect-configs`) | `1` | `compact` | replicated (≥3 in production) |
| status (`connect-status`) | several | `compact` | replicated (≥3 in production) |

These settings are the Kafka Connect user guide's recommendation for the worker
topics, because the auto-created defaults "may not be best suited" and can be
configured for deletion rather than compaction
([Apache Kafka — Kafka Connect user guide (distributed mode)](https://kafka.apache.org/37/documentation/#connect_running)).

### Recommended `topics` input

```json
[
  {
    "name": "schema-history.my-connector",
    "partitions": 1,
    "configs": {
      "cleanup.policy": "delete",
      "retention.ms": "-1",
      "retention.bytes": "-1"
    }
  },
  {
    "name": "connect-offsets",
    "partitions": 25,
    "configs": { "cleanup.policy": "compact" }
  },
  {
    "name": "connect-configs",
    "partitions": 1,
    "configs": { "cleanup.policy": "compact" }
  },
  {
    "name": "connect-status",
    "partitions": 5,
    "configs": { "cleanup.policy": "compact" }
  }
]
```

Replication factor is a cluster-durability choice left to the consumer; the
project applies whatever `configs` are supplied.

## Example configs

Three ready-made files, copyable as-is or as a starting point, all matching the
`PROPELLER_INPUT_topics` / `PROPELLER_INPUT_topics_file` shape:

- [`topics-mariadb-recommended.json.example`](topics-mariadb-recommended.json.example)
  — the superset above: schema history plus the three Kafka Connect internal
  topics, with the settings this README recommends.
- [`topics-oracle-recommended.json.example`](topics-oracle-recommended.json.example)
  — the same superset for the Oracle flavour. The schema history
  topic's *settings* are identical to MariaDB's — Debezium documents them as
  shared across every connector that uses a schema history topic at all
  ([Storing state of a Debezium connector](https://debezium.io/documentation/reference/stable/configuration/storage.html)
  lists MySQL, SQL Server and Oracle together; PostgreSQL is the exception,
  since it reads schema from `pg_catalog` rather than replaying DDL). What
  changes is only the *name*: Oracle's own topic-naming convention is
  `<topicPrefix>.<schemaName>.<tableName>` for change-event topics, and
  Debezium "applies similar naming conventions" to the schema history topic
  ([Default names of Kafka topics for the Oracle connector](https://docs.redhat.com/ko/documentation/red_hat_build_of_debezium/3.2.7/html/debezium_user_guide/default-names-of-kafka-topics-that-receive-debezium-oracle-change-event-records)).
  The example uses `ORCLPDB1`, Oracle's own default pluggable database name in
  its tutorials, in place of a schema name — replace it with the consumer's
  actual PDB or schema.
- [`topics-schema-history-only.json.example`](topics-schema-history-only.json.example)
  — schema history alone (MariaDB naming; adjust for Oracle), for a consumer
  confident that MSK Connect (or the Connect worker) will create the internal
  topics with acceptable settings, or that is pre-creating them elsewhere.

Copy one, rename it (drop the `.example` suffix), and adjust the topic names —
the schema history topic name should match the `schema_history_topic` wired
into `msk-connect-debezium`. Then either inline its contents as
`PROPELLER_INPUT_topics`, or lay it down as `topics.json` next to `topics.py`
(directly, or via an overlay — see [Pipeline wiring](#pipeline-wiring)) and set
`PROPELLER_INPUT_topics_file=topics.json`.

## Both cluster shapes

The project supports both authentication forms with no built-in assumption about
which is in use.

**IAM + TLS cluster** (e.g. the framework's `msk-cluster`) — `security_protocol`
is `SASL_SSL`. `topics.py` builds the admin client with SASL/OAUTHBEARER and an
AWS MSK IAM token minted from `AWS_REGION`:

```bash
export PROPELLER_INPUT_security_protocol=SASL_SSL
export PROPELLER_INPUT_bootstrap_servers="b-1.mycluster.abc.kafka.eu-west-1.amazonaws.com:9098"
export AWS_REGION=eu-west-1
```

**Unauthenticated PLAINTEXT cluster** — `security_protocol` is `PLAINTEXT`; no
SASL, no token, `AWS_REGION` unused:

```bash
export PROPELLER_INPUT_security_protocol=PLAINTEXT
export PROPELLER_INPUT_bootstrap_servers="broker-1.internal:9092"
```

## Outputs

None consumed downstream. The connector project already knows the topic names —
it is the consumer that passed them into this project's `topics` input in the
first place — so there is nothing for this project to publish back.

## Idempotency and `destroy`

- **`plan`** echoes the bootstrap servers, the security protocol, and the topics
  it would create. It opens no connection and creates nothing.
- **`apply`** creates each topic; an already-existing topic is success and its
  configuration is left unchanged. Re-running changes nothing.
- **`destroy`** is a deliberate no-op that deletes nothing. Dropping a CDC topic
  loses schema history or consumer offsets and forces a recovery or full
  re-snapshot — an operator decision, not the deployment's.

## Standalone invocation

The project runs standalone through `just` with the inputs supplied as
environment variables:

Inline (`PROPELLER_INPUT_topics`):

```bash
export PROPELLER_INPUT_bootstrap_servers="b-1.mycluster.abc.kafka.eu-west-1.amazonaws.com:9098"  # required
export PROPELLER_INPUT_security_protocol=SASL_SSL                                                # required
export AWS_REGION=eu-west-1                                                                       # required for SASL_SSL
export PROPELLER_INPUT_topics='[
  {"name":"schema-history.my-connector","partitions":1,"configs":{"cleanup.policy":"delete","retention.ms":"-1","retention.bytes":"-1"}},
  {"name":"connect-offsets","partitions":25,"configs":{"cleanup.policy":"compact"}},
  {"name":"connect-configs","partitions":1,"configs":{"cleanup.policy":"compact"}},
  {"name":"connect-status","partitions":5,"configs":{"cleanup.policy":"compact"}}
]'

just plan     # report the topics it would create (no connection opened)
just apply    # create the topics
just destroy  # no-op
```

Or from a file (copy an [example config](#example-configs) to `topics.json`
next to `topics.py` first):

```bash
export PROPELLER_INPUT_bootstrap_servers="b-1.mycluster.abc.kafka.eu-west-1.amazonaws.com:9098"
export PROPELLER_INPUT_security_protocol=SASL_SSL
export AWS_REGION=eu-west-1
export PROPELLER_INPUT_topics_file=topics.json

just plan
just apply
```

`apply` requires in-VPC network reachability to the brokers, and AWS credentials
for the IAM token when `security_protocol` is `SASL_SSL`.

## Sleep/wake and teardown

No sleep/wake recipe is implemented for any CDC project. Implementing sleep modes
is out of scope; the consumer wiring the pipeline owns that decision, and these
projects document the constraints only. The constraints below are repeated on
every CDC project's README so the ordering is visible wherever an operator
starts:

- The connector must be removed **before** its source database and its Kafka
  cluster.
- Under the framework's MSK sleep semantics (destroy-only), a sleeping cluster
  loses its topics and consumer offsets. **On wake, this project must run again
  to recreate the topics before the connector starts** — otherwise the
  connector has no schema history or offset topic to attach to. Debezium then
  performs a recovery snapshot.
- A sleep outlasting the configured binary-log retention window turns a CDC gap
  into a full re-snapshot.

## What does NOT belong here

- **Preparing the source database** — that is `cdc-prepare-mariadb` (CDC user,
  grants, binary-logging preconditions).
- **The connector and its IAM role** — that is `msk-connect-debezium`.
- **Changing cluster-wide Kafka configuration** — this project only creates
  topics; it never touches broker or cluster settings, and never enables
  automatic topic creation.

## References

- [Debezium connector for MariaDB — schema history topic (2.7)](https://debezium.io/documentation/reference/2.7/connectors/mariadb.html)
- [A Note On Database History Topic Configuration](https://debezium.io/blog/2018/03/16/note-on-database-history-topic-configuration/)
- [Auto-creating Debezium Change Data Topics](https://debezium.io/blog/2020/09/15/debezium-auto-create-topics/)
- [Apache Kafka — Kafka Connect user guide (distributed mode)](https://kafka.apache.org/37/documentation/#connect_running)
- [Storing state of a Debezium connector](https://debezium.io/documentation/reference/stable/configuration/storage.html)
- [Default names of Kafka topics for the Oracle connector](https://docs.redhat.com/ko/documentation/red_hat_build_of_debezium/3.2.7/html/debezium_user_guide/default-names-of-kafka-topics-that-receive-debezium-oracle-change-event-records)
