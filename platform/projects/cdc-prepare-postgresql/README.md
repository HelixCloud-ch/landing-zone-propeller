# cdc-prepare-postgresql

Prepares one RDS for PostgreSQL database for Debezium CDC. It has no Terraform
state. `apply` runs `prepare.py` in the shared `cdc` Python env
(`platform/shared/python/cdc`) through `py-run`. Every run is idempotent.

The scope is one database (`db_name`), not the whole instance. A replication
slot works on one database only.

## What it does

1. Reads the admin credential from the SSM parameter that
   `admin_credential_parameter` names.
2. Verifies the logical-replication preconditions and plans the publication.
   If one fails, it stops and changes nothing.
3. Resolves the CDC credential from two SecureString parameters (see below).
4. Creates the CDC role if it does not exist. Grants it `rds_replication`,
   `USAGE` on the schemas and `SELECT` on their tables. The role has no
   superuser right and no `REPLICATION` attribute. On RDS, the
   `rds_replication` role gives the right to manage and read logical slots.
   Then checks that the role can read the tables (see Grants).
5. Creates or syncs the publication (see below).
6. Logs in as the CDC user. If the login fails, the database password and the
   SSM parameter differ, and the run fails.

`destroy` does nothing. Drop the CDC role manually if you need to.

## Inputs

Inputs arrive as `PROPELLER_INPUT_*` variables.

- `db_host`: required. The database endpoint.
- `db_port`: default `5432`.
- `db_name`: required. The database to capture.
- `admin_credential_parameter`: required. Name of the SSM parameter with the
  admin login.
- `admin_username`: the admin user name, if the admin parameter holds only the
  password.
- `cdc_username`: required. The CDC role name. Used only when the username
  parameter does not exist yet.
- `cdc_username_parameter`, `cdc_password_parameter`: required. Names of the
  two CDC credential parameters. Give the connector the same names.
- `kms_key_id`: the key for parameters this project creates. Default
  `alias/aws/ssm`.
- `schemas`: JSON list. The CDC role gets `USAGE` and `SELECT` on all tables of
  these schemas. Default `["public"]`.
- `manage_publication`: `true` (default) or `false`. See Publication.
- `publication_name`: default `dbz_publication`.
- `publication_tables`: JSON list of `schema.table`. Empty (default) means all
  tables. Needs `manage_publication=true`. The schema of each entry must be in
  `schemas`, or the run stops with exit code 2.
- `slot_name`: default `debezium`. Used only for the slot report and the
  `destroy` message. The connector creates the slot.
- `ssl_mode`: default `require`. See TLS.
- `ssl_root_cert`: path of a CA bundle file. See TLS.

## Grants

The `schemas` grant covers the tables that exist at run time. Run `apply` again
after you add a table. The CDC role gets no grant outside `schemas`. For this
reason, a `publication_tables` entry in another schema is an input error.

`GRANT SELECT ON ALL TABLES` gives only a warning for a table that the admin
login does not own and cannot grant on, if the admin has some other privilege
on it. The grant then does nothing and the statement passes. For this reason,
after the grants, the run checks `has_table_privilege` for the CDC role on every
table in `schemas`:

- A table in `publication_tables` without `SELECT` stops the run with exit code
  1, before the publication changes. The message names the tables. Grant
  `SELECT` on them to the CDC role as the table owner, then run again.
- Any other table without `SELECT` only gives a warning. It shows the first
  ten names and the count. With `manage_publication=false`, all tables are in
  this group.

If the admin login has no privilege at all on a table, PostgreSQL stops the
`GRANT` with a permission error, and the run fails with exit code 1.

## Admin credential

The admin parameter holds a JSON document `{"username": ..., "password": ...}`,
or only the password. For only the password, set `admin_username`.

The pipeline examples of the sibling projects use an input named
`rds-appdb.admin_credential_parameter_name`. No `rds-*` project has that
output. `rds-postgresql` outputs a Secrets Manager ARN, not an SSM parameter
name. This project reads SSM only. Create the SSM parameter before the first
run, and pass its name as a literal, as in the example below.

## CDC credential

The CDC credential is in two scalar parameters, because the connector reads
each with the MSK Connect SSM config provider, and that provider cannot read a
key out of a JSON document.

- An existing parameter is the source of truth. This project never changes it.
- A missing parameter is created: the username from `cdc_username`, the
  password generated.
- An existing CDC role keeps its password. There is no rotation.

No credential value is printed. The password is sent in `CREATE ROLE`, which
cannot bind parameters. If the instance has `log_statement` set to `ddl`,
`mod` or `all`, the statement can reach the database log. The run prints a
warning in that case.

## Preconditions

The project verifies these. It cannot set them.

- `wal_level` is `logical`. Set `rds.logical_replication=1` in the DB parameter
  group. It is a static parameter: reboot the instance to apply it. Run this
  project only after the reboot. The error message tells which of the two
  steps is missing.
- A free replication slot exists (`max_replication_slots`), or the slot
  `slot_name` exists already.
- A slot named `slot_name` is a `pgoutput` slot on `db_name`. Debezium cannot
  use another one.

The run only reports these, and does not fail: slot and WAL sender use,
`max_slot_wal_keep_size` of `-1` (no limit), `log_statement`, a server older
than version 10, and the tables in `schemas` that the CDC role cannot read
(unless the table is in `publication_tables`: see Grants).

## Publication

Debezium with `pgoutput` reads changes from a publication. Creating a
`FOR ALL TABLES` publication needs a superuser right, and adding a table needs
table ownership. The CDC role has neither. With `manage_publication=true`, the
admin login creates the publication instead.

- `publication_tables` empty: `FOR ALL TABLES`. Future tables are included.
- `publication_tables` set: `FOR TABLE ...`. The run syncs the list on every
  run. The admin login must own the tables (not verified on RDS).
- A publication of the other kind (all tables or a list) is not switched. The
  run stops and says what to drop.

A publication that publishes `UPDATE` and `DELETE` makes those statements fail
on a table with no primary key and no replica identity. Before the project
creates or changes the publication, it checks the tables in scope. If a table
has no primary key and its replica identity is `default` or `nothing`, the run
stops, changes nothing and names the tables. Add a key, or run
`ALTER TABLE ... REPLICA IDENTITY FULL`. The project never alters application
tables. If the publication exists already, the same check only prints a
warning, so a later `wake` is not blocked.

With `manage_publication=false`, the project does not create, sync or check the
publication. It only reports whether it exists. The DBA or the connector must
create it:

- The DBA creates it before the connector starts. The connector then uses
  `publication.autocreate.mode=disabled`.
- The connector creates it. `filtered` mode needs `CREATE` on the database and
  ownership of the tables. `all_tables` (the Debezium default) needs high
  privileges and fails for the CDC role.

In every case, the connector needs `plugin.name=pgoutput`, `publication.name`
equal to `publication_name`, and `slot.name` equal to `slot_name`. A managed
publication needs `publication.autocreate.mode=disabled`.
`table.include.list` stays on the connector. Keep it equal to
`publication_tables`.

The `msk-connect-debezium` project sets `plugin.name=pgoutput` and
`publication.autocreate.mode=disabled` by default, and leaves `publication.name`
to the Debezium default `dbz_publication`, which is the default
`publication_name`. It derives `slot.name` from the connector `identifier`, not
from `slot_name`. If you want the slot report of this project to look at the
connector slot, give `slot_name` the name that the connector will use: the
derived name (the `identifier` in lowercase, with `-` changed to `_`) or your
`slot.name` override. This project runs before the connector, so the
`slot_name` output of
[`msk-connect-debezium`](../msk-connect-debezium/README.md#postgresql) does not
exist yet.

## WAL retention and the replication slot

PostgreSQL has no time-based log retention. A replication slot keeps WAL until
its reader confirms it. An unread or orphaned slot keeps WAL without a limit
and can fill the instance storage
([RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.FeatureSupport.LogicalReplication.html)).
`max_slot_wal_keep_size` is `-1` by default.

- The connector creates the slot at its first start. It stays after the
  connector is removed.
- A database with little traffic on a busy instance can also grow WAL, because
  the slot is not confirmed. Debezium names `heartbeat.interval.ms` for this.
- Alarm on the CloudWatch metrics `ReplicationSlotDiskUsage`,
  `OldestReplicationSlotLag` and `TransactionLogsDiskUsage`.
- Each run reports the state of the slot `slot_name` and warns when it is
  inactive and holds WAL.

`destroy` and `sleep` do nothing, and `wake` runs `apply`. `destroy` prints the
slot name and the command to drop it. Remove the connector before the
database. Drop the slot yourself after that, and remove the connector offsets
too. A new slot with an old Kafka offset can skip changes without any error.
If only the connector sleeps and the database stays up, the slot keeps growing.

## Major version upgrade

An RDS major version upgrade from a version before 17 needs all logical slots
dropped. Debezium then finds no slot. A new slot cannot return the changes of
the downtime, and the connector skips them without any error. Follow the
Debezium upgrade procedure and check the AWS note on the source version.

## TLS

`ssl_mode` applies to the admin login and to the CDC login. The default is
`require`: the traffic is encrypted but the certificate is not checked. RDS for
PostgreSQL 15 and later forces SSL by default.

`verify-ca` and `verify-full` need a CA bundle file on the runner. Set
`ssl_root_cert`, or the variable `PGSSLROOTCERT`. If neither is set, or the
file does not exist, the run stops with exit code 2. The deploy-runner image
has `ca-certificates` but not the RDS bundle. `verify-full` also needs
`db_host` to be the RDS endpoint name, because the server certificate carries
it.

The connector has its own TLS setting (`database.sslmode`). This project does
not set it.

## Exit codes

`0` ok. `1` a database or AWS failure, or a failed precondition. `2` an input
error.

## Runner

Use a runner in the VPC that can reach the database and the SSM endpoint. On
the deploy-runner image, add the `cdc` env to `python_envs` so the run needs no
internet access. This project adds `psycopg` to that env, so the image needs a
rebuild first.

## Pipeline example

```yaml
- project: cdc-prepare-appdb
  source: propeller:cdc-prepare-postgresql
  target: <account>
  runner: <in-vpc runner>
  inputs:
    - name: rds-appdb.address
      var: db_host
    - var: db_name
      literal: appdb
    - var: admin_credential_parameter
      literal: /platform/appdb/admin-credential
    - var: admin_username
      literal: postgres
    - var: cdc_username
      literal: cdc_user
    - var: cdc_username_parameter
      literal: /platform/appdb/cdc-username
    - var: cdc_password_parameter
      literal: /platform/appdb/cdc-password
```

The `rds-appdb` step is a placeholder for the step that creates the database.

## What does NOT belong here

- **The connector.** This project only prepares the database. The Debezium
  connector, its plugin and its topics are other projects.
- **`rds.logical_replication` and the reboot.** These belong to the database
  project and its parameter group.
- **The replication slot.** The connector creates it. This project only
  reports it.
- **Dropping the role, the publication or the slot.** `destroy` does nothing.

## Test

```bash
uv run --project platform/shared/python/cdc pytest platform/projects/cdc-prepare-postgresql
```

## References

- [Performing logical replication for Amazon RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.FeatureSupport.LogicalReplication.html)
- [Debezium PostgreSQL connector](https://debezium.io/documentation/reference/2.7/connectors/postgresql.html)
- [PostgreSQL CREATE PUBLICATION](https://www.postgresql.org/docs/current/sql-createpublication.html)
- [Working with REPLICA IDENTITY FULL on RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.ReplicaIdentityFull.html)
- [Reestablishing logical replication after a major upgrade](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.pglogical.recover-replication-after-upgrade.html)
- [Amazon CloudWatch metrics for Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html)
- [Using SSL with an RDS for PostgreSQL DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html)
- [Using SSL/TLS to encrypt a connection to a DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html)
- [MSK Connect config providers](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-config-provider.html)
