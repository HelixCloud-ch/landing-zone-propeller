# CDC deployment verification

A checklist for the first deployment of the Debezium change-data-capture chain
(`cdc-prepare-*`, `cdc-topics`, `msk-connect-plugin`, `msk-connect-debezium`)
in a new environment. These projects are tested offline only. The items below
need a live source database, Kafka cluster, or MSK Connect worker, so they
cannot be checked by the projects' own tests.

Items marked **blocking** must pass before production use. The others confirm
an assumption the projects document. If one fails, the fix is usually a
configuration change, not a code change.

## All engines

- **IAM authentication for schema history.** With
  `client_authentication = "IAM"`, the connector's schema-history producer and
  consumer use the `AWS_MSK_IAM` login module. The plugin artifact does not
  bundle `aws-msk-iam-auth`; confirm the connector reaches `RUNNING` and writes
  to the schema history topic. If it fails with a class-not-found error for
  `software.amazon.msk.auth.iam`, add the jar to the plugin ZIP. See
  [`msk-connect-debezium` module](../platform/shared/modules/msk-connect-debezium/README.md).
- **Kafka Connect internal topics.** Confirm the offset, config and status
  topics have `cleanup.policy=compact` after the first start, whether
  `cdc-topics` pre-created them or MSK Connect did. A `delete` policy here
  eventually drops connector state. See [`cdc-topics`](../platform/projects/cdc-topics/README.md).
- **Routed topics.** If the connector uses a topic-routing transform (for
  example the outbox event router), confirm every target topic exists. MSK
  defaults `auto.create.topics.enable` to `false`.
- **Debezium version.** A plugin version catalogued with `enabled: false` has
  not been run on MSK Connect. Before enabling it, deploy a test connector on
  the target `kafkaconnect_version` and confirm it reaches `RUNNING` and
  streams changes. See [`msk-connect-plugin-artifact`](../platform/projects/msk-connect-plugin-artifact/README.md#choosing-a-version).
- **Restart recovery.** Restart the connector (or replace it) and confirm it
  resumes from its stored offsets without a new snapshot.

## MariaDB

- **Binary log retention.** Confirm `binlog retention hours` on the instance
  covers the longest expected connector outage, including any sleep window.
  Past it, the connector needs a full re-snapshot. See
  [`cdc-prepare-mariadb`](../platform/projects/cdc-prepare-mariadb/README.md).

## Oracle

The Oracle path has not been run against a live instance at all. Treat every
item here as part of the first deployment.

- **blocking — LogMiner CPU impact.** LogMiner runs on the source instance.
  Measure CPU and I/O on the source under representative write load with the
  connector streaming, and compare against the instance's headroom. This
  cannot be estimated offline.
- **blocking — grants on the target architecture.** Run `cdc-prepare-oracle`
  and then start the connector. On RDS for Oracle CDB instances, some
  community reports describe `ORA-01031` even with the documented grants.
  Confirm the connector starts mining without privilege errors on the actual
  architecture (non-CDB, single-tenant or multi-tenant CDB). See
  [`cdc-prepare-oracle`](../platform/projects/cdc-prepare-oracle/README.md#the-grant-list).
- **Container clause.** The project issues grants without a `CONTAINER`
  clause. On a multitenant CDB, confirm whether the grants must be issued with
  `CONTAINER=ALL` (and `SET CONTAINER` granted), and adjust if so.
- **Archived log retention.** Confirm `archivelog retention hours` covers the
  longest expected connector outage, as for the MariaDB binary log.
- **Log mining strategy.** If `online_catalog` is used, confirm that schema
  changes to captured tables are rare enough to accept its limitation (it
  cannot track DDL against captured tables).

## References

- [Debezium connector for Oracle (2.7)](https://debezium.io/documentation/reference/2.7/connectors/oracle.html)
- [Debezium connector for MariaDB (2.7)](https://debezium.io/documentation/reference/2.7/connectors/mariadb.html)
- [Create a Debezium source connector (MSK Connect)](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-debeziumsource-connector-example-steps.html)
- [RDS for Oracle database architecture](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/oracle-multi-architecture.html)
