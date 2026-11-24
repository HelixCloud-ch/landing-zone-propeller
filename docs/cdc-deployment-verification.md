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

## PostgreSQL

[`cdc-prepare-postgresql`](../platform/projects/cdc-prepare-postgresql/README.md) is tested offline and against a
stock PostgreSQL container. It has not run against an RDS instance. The container has no
`rds_replication` role with real rights, so it cannot create a slot as the CDC
user. Treat the slot items below as part of the first deployment.

- **blocking — reboot after `rds.logical_replication`.** The parameter is
  static. Confirm `SHOW wal_level` returns `logical` before the first
  `cdc-prepare-postgresql` run. The project stops if it does not.
- **blocking — connector reaches `RUNNING`.** Deploy
  [`msk-connect-debezium`](../platform/projects/msk-connect-debezium/README.md#postgresql)
  with `engine = "postgresql"`. Confirm the connector reaches `RUNNING`, takes
  the snapshot, and streams changes. Use the worker logs if it does not (see
  the log delivery section of the module README).
- **blocking — streaming as the CDC user.** Confirm that the CDC role
  (`rds_replication`, `SELECT`, no superuser right) is enough on RDS for the
  snapshot and for the slot creation.
- **blocking — slot is active with `pgoutput`.** After the first start, run
  `SELECT slot_name, plugin, active FROM pg_replication_slots`. Confirm there is
  one row for the connector with `plugin = pgoutput` and `active = true`. The
  slot name is the name that the connector uses: derived from `identifier`
  (lowercase, `-` becomes `_`), or your `slot.name` override. The `slot_name`
  output of the connector project shows it after the deploy. Confirm that the
  `slot_name` input of `cdc-prepare-postgresql` has the same value, if you
  want its slot report to show this slot.
- **Publication used.** With the default `publication.autocreate.mode=disabled`,
  confirm the connector starts without a publication error, and that
  `pg_publication_tables` lists the captured tables for the publication it
  uses (`dbz_publication`, or the name you set in `publication.name`). If
  `cdc-prepare-postgresql` runs with `manage_publication=false` and you
  override the mode to `filtered`, confirm the CDC role can create and alter
  the publication (`CREATE` on the database, ownership of the tables).
- **Connector SSL mode.** The connector sets `database.sslmode=require`.
  Confirm the session of the CDC user is encrypted: the `ssl` column of
  `pg_stat_ssl` is `true` for its `pid`. For `verify-ca` or `verify-full`,
  confirm that the CA file is on the MSK Connect worker. The projects do not
  provide it.
- **Debezium 3.x on MSK Connect.** The default plugin (2.7.4.Final) is tested
  on PostgreSQL 12 to 16 only. RDS for PostgreSQL 17 and 18 need a 3.x
  plugin. No 3.x plugin has run on MSK Connect (all are `enabled: false` in the
  catalogue). Before you use one, deploy a test connector and repeat the items
  above.
- **blocking — WAL retention and slot cleanup.** An unread or orphaned
  replication slot keeps WAL and can fill the instance storage.
  `max_slot_wal_keep_size` is `-1` by default. Create alarms on
  `ReplicationSlotDiskUsage`, `OldestReplicationSlotLag` and
  `TransactionLogsDiskUsage`. After you remove a connector, check
  `pg_replication_slots` for a slot that is not active, and drop it by hand.
  Remove the connector offsets too, or a new slot with an old offset can skip
  changes without any error.
- **Slot over stop and start.** Stop and start the instance, and confirm the
  slot stays. Confirm the connector resumes without a new snapshot.
- **Publication ownership.** With `publication_tables` set, confirm the admin
  login can add tables that another role owns. If it cannot, create the
  publication as the table owner and set `manage_publication` to `false`.
- **Replica identity.** The project stops when a table in scope has no primary
  key and its replica identity is `default` or `nothing`. Check the tables the
  message names. Add a key, or run `ALTER TABLE ... REPLICA IDENTITY FULL`.
- **Low traffic database.** On an instance with a busy database next to the
  captured one, confirm the slot position moves. If it does not, set
  `heartbeat.interval.ms` on the connector (it is off by default). If topic
  auto-creation is off, create the topic `__debezium-heartbeat.<topic_prefix>`
  first.
- **TLS of the preparation step.** The `ssl_mode` of `cdc-prepare-postgresql`
  defaults to `require`. For `verify-full`, confirm the
  runner has the RDS CA bundle and `db_host` is the endpoint name.
- **Major version upgrade.** An upgrade from a version before 17 needs all
  logical slots dropped, and a new slot cannot return the changes of the
  downtime. Follow the procedures in the references before you upgrade.

## References

- [Debezium connector for PostgreSQL (2.7)](https://debezium.io/documentation/reference/2.7/connectors/postgresql.html)
- [Performing logical replication for Amazon RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.FeatureSupport.LogicalReplication.html)
- [Reestablishing logical replication after a major upgrade](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.pglogical.recover-replication-after-upgrade.html)
- [Amazon CloudWatch metrics for Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html)
- [Debezium connector for Oracle (2.7)](https://debezium.io/documentation/reference/2.7/connectors/oracle.html)
- [Debezium connector for MariaDB (2.7)](https://debezium.io/documentation/reference/2.7/connectors/mariadb.html)
- [Create a Debezium source connector (MSK Connect)](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-debeziumsource-connector-example-steps.html)
- [RDS for Oracle database architecture](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/oracle-multi-architecture.html)
