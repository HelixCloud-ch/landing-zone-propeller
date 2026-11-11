# cdc-prepare-mariadb

Prepares an RDS for MariaDB database for Debezium CDC. It has no Terraform
state. `apply` runs `prepare.py` in the shared `cdc` Python env
(`platform/shared/python/cdc`) through `py-run`. Every run is idempotent.

## What it does

1. Reads the admin credential from the SSM parameter that
   `admin_credential_parameter` names.
2. Verifies the binary-log preconditions. If one fails, it stops and changes
   nothing.
3. Resolves the CDC credential from two SecureString parameters (see below).
4. Creates the CDC user if it does not exist. Grants `SELECT`, `RELOAD`,
   `SHOW DATABASES`, `REPLICATION SLAVE`, `REPLICATION CLIENT` and
   `LOCK TABLES` on `*.*`, as in Debezium's
   [user setup](https://debezium.io/documentation/reference/stable/connectors/mariadb.html#mariadb-creating-user).
   RDS does not allow a global read lock, so the snapshot locks each table,
   which needs `LOCK TABLES`.
5. Sets `binlog retention hours` with `mysql.rds_set_configuration`, on every
   run.
6. Logs in as the CDC user. If the login fails, the database password and the
   SSM parameter differ, and the run fails.

`destroy` does nothing. Drop the CDC user manually if you need to.

## Inputs

Inputs arrive as `PROPELLER_INPUT_*` variables.

- `db_host`: required. The database endpoint.
- `db_port`: default `3306`.
- `admin_credential_parameter`: required. Name of the SSM parameter with the
  admin login.
- `admin_username`: the admin user name, if the admin parameter holds only the
  password.
- `cdc_username`: required. The CDC user name (`[A-Za-z0-9_]`). Used only when
  the username parameter does not exist yet.
- `cdc_username_parameter`, `cdc_password_parameter`: required. Names of the
  two CDC credential parameters. Give `msk-connect-debezium` the same names.
- `binlog_retention_hours`: required, for example `168`.
- `kms_key_id`: the key for parameters this project creates. Default
  `alias/aws/ssm`.

## Credentials

The admin parameter holds a JSON document `{"username": ..., "password": ...}`,
or only the password. For only the password, set `admin_username`.

The CDC credential is in two scalar parameters, because the connector reads
each with the MSK Connect SSM config provider, and that provider cannot read a
key out of a JSON document.

- An existing parameter is the source of truth. This project never changes it.
- A missing parameter is created: the username from `cdc_username`, the
  password generated.
- An existing CDC user keeps its password. There is no rotation.

No credential value is printed.

## Preconditions

The project verifies these. It does not set them.

- `log_bin` is `ON`. On RDS, set the automated backup retention
  (`backup_retention_period`) to more than 0.
- `binlog_format` is `ROW` and `binlog_row_image` is `FULL` (DB parameter
  group).
- `log_bin_compress` is off.

## Runner

Use a runner in the VPC that can reach the database and the SSM endpoint. On
the deploy-runner image, add the `cdc` env to `python_envs` so the run needs no
internet access.

## Pipeline example

```yaml
- project: cdc-prepare-appdb
  source: propeller:cdc-prepare-mariadb
  target: <account>
  runner: <in-vpc runner>
  inputs:
    - name: rds-appdb.endpoint_address
      var: db_host
    - name: rds-appdb.admin_credential_parameter_name
      var: admin_credential_parameter
    - var: admin_username
      literal: admin
    - var: cdc_username
      literal: cdc_user
    - var: cdc_username_parameter
      literal: /platform/appdb/cdc-username
    - var: cdc_password_parameter
      literal: /platform/appdb/cdc-password
    - var: binlog_retention_hours
      literal: "168"
```

## Sleep and teardown

- Remove the connector before its database and its Kafka cluster.
- A sleep longer than the binlog retention makes the connector re-snapshot.

## Test

```bash
uv run --project platform/shared/python/cdc pytest platform/projects/cdc-prepare-mariadb
```

## References

- [Debezium MariaDB connector](https://debezium.io/documentation/reference/stable/connectors/mariadb.html)
- [RDS mysql.rds_set_configuration](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/mysql_rds_set_configuration.html)
- [MSK Connect config providers](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-config-provider.html)
