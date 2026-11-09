# cdc-prepare-oracle

Prepares an RDS for Oracle database for Debezium CDC with LogMiner. It has no
Terraform state. `apply` runs `prepare.py` in the shared `cdc` Python env
(`platform/shared/python/cdc`) through `py-run`. Every run is idempotent.

Not yet verified against a live instance. Read the Oracle part of
[`docs/cdc-deployment-verification.md`](../../../docs/cdc-deployment-verification.md#oracle)
first.

## What it does

1. Reads the admin credential from the SSM parameter that
   `admin_credential_parameter` names.
2. Verifies the LogMiner preconditions. If one fails, it stops and changes
   nothing.
3. Resolves the CDC credential from two SecureString parameters (see below).
4. Creates the CDC user if it does not exist, and grants the LogMiner
   privileges (see below).
5. Sets `archivelog retention hours` with
   `rdsadmin.rdsadmin_util.set_configuration`, on every run.
6. Logs in as the CDC user. If the login fails, the database password and the
   SSM parameter differ, and the run fails.

`destroy` does nothing. Drop the CDC user manually if you need to.

## Inputs

Inputs arrive as `PROPELLER_INPUT_*` variables.

- `db_host`: required. The database endpoint.
- `db_port`: default `1521`.
- `service_name`: required. The service name.
- `pdb_name`: the pluggable database service, on a CDB. Empty for a non-CDB.
- `admin_credential_parameter`: required. Name of the SSM parameter with the
  admin login.
- `admin_username`: the admin user name, if the admin parameter holds only the
  password.
- `cdc_username`: required. The CDC user name, a bare identifier
  (`[A-Za-z][A-Za-z0-9_#$]`, up to 30 characters). Oracle stores it in upper
  case. Used only when the username parameter does not exist yet.
- `cdc_username_parameter`, `cdc_password_parameter`: required. Names of the
  two CDC credential parameters. Give `msk-connect-debezium` the same names.
- `archivelog_retention_hours`: required, for example `24`.
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
  password generated (30 characters).
- The password goes in double quotes in `CREATE USER`. It must not contain `"`
  and must fit in 30 bytes.
- An existing CDC user keeps its password. There is no rotation.

No credential value is printed.

## Grants

The list follows Debezium's
[LogMiner user setup](https://debezium.io/documentation/reference/stable/connectors/oracle.html#oracle-create-users-logminer).

- System privileges, with `GRANT`: `CREATE SESSION`, `SELECT ANY TABLE`,
  `FLASHBACK ANY TABLE`, `SELECT ANY TRANSACTION`, `SELECT_CATALOG_ROLE`,
  `EXECUTE_CATALOG_ROLE`, `LOGMINING`, `CREATE TABLE`, `LOCK ANY TABLE`,
  `CREATE SEQUENCE`.
- SYS objects, with `rdsadmin.rdsadmin_util.grant_sys_object`, because the RDS
  master user is not SYS: `EXECUTE` on `DBMS_LOGMNR` and `DBMS_LOGMNR_D`;
  `SELECT` on the `V_$` views LogMiner reads.

Open points:

- The grants have no `CONTAINER` clause. On a multitenant CDB, confirm whether
  Debezium needs `CONTAINER=ALL` and `SET CONTAINER`.
- Community reports describe `ORA-01031` on RDS CDB instances even with these
  grants.

## Preconditions

The project verifies these. It does not set them.

- `LOG_MODE` is `ARCHIVELOG`. On RDS, set the automated backup retention
  (`backup_retention_period`) to more than 0.
- Minimal supplemental logging is on:
  `rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD')`.
- Primary key supplemental logging is on:
  `rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD', 'PRIMARY KEY')`.

## Runner

Use a runner in the VPC that can reach the database and the SSM endpoint. On
the deploy-runner image, add the `cdc` env to `python_envs` so the run needs no
internet access. `oracledb` runs in thin mode: it needs no Oracle client.

## Pipeline example

```yaml
- project: cdc-prepare-appdb
  source: propeller:cdc-prepare-oracle
  target: <account>
  runner: <in-vpc runner>
  inputs:
    - name: rds-appdb.endpoint_address
      var: db_host
    - name: rds-appdb.db_name
      var: service_name
    - name: rds-appdb.admin_credential_parameter_name
      var: admin_credential_parameter
    - var: admin_username
      literal: admin
    - var: cdc_username
      literal: CDC_USER
    - var: cdc_username_parameter
      literal: /platform/appdb/cdc-username
    - var: cdc_password_parameter
      literal: /platform/appdb/cdc-password
    - var: archivelog_retention_hours
      literal: "24"
```

## Sleep and teardown

- Remove the connector before its database and its Kafka cluster.
- A sleep longer than the archived log retention makes the connector
  re-snapshot.

## Test

```bash
uv run --project platform/shared/python/cdc pytest platform/projects/cdc-prepare-oracle
```

## References

- [Debezium Oracle connector](https://debezium.io/documentation/reference/stable/connectors/oracle.html)
- [RDS: grant privileges on SYS objects](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.Oracle.CommonDBATasks.TransferPrivileges.html)
- [RDS for Oracle architectures (CDB, non-CDB)](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/oracle-multi-architecture.html)
- [ORA-00988: password quoting](https://docs.oracle.com/en/error-help/db/ora-00988/)
- [MSK Connect config providers](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-config-provider.html)
