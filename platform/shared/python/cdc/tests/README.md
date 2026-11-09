# CDC integration tests

These tests run the real CDC scripts (`cdc-prepare-mariadb`,
`cdc-prepare-oracle`, `cdc-topics`) against real MariaDB, Oracle and Kafka in
Docker. They find what the unit tests cannot: SQL that the database rejects,
real grants, and real broker behaviour.

SSM is faked in memory. The tests need Docker, but no AWS access.

## Run

```bash
just test-cdc-integration   # start the services, run the tests, stop the services
```

During development, keep the services running:

```bash
just cdc-up                 # start and wait until ready (Oracle: about a minute the first time)
env UV_PYTHON_PREFERENCE=only-managed UV_PYTHON_INSTALL_DIR="$PWD/dist/test-python" \
  UV_PROJECT_ENVIRONMENT="$PWD/dist/cdc-venv" \
  uv run --project platform/shared/python/cdc pytest platform/shared/python/cdc/tests -k oracle
just cdc-down               # stop and delete the data
```

The recipes use a uv-managed Python and a venv in `dist/`. A Python installed
on the machine is not used: a Python 3.14 pre-release crashes when it loads
`oracledb`.

## Services

`compose.yaml` starts three services on localhost. Each has a healthcheck, so
`just cdc-up` returns when all three are ready.

- MariaDB 11.4 on port 33306. Binary log on, `ROW`, `FULL`.
  `mariadb-init.sql` adds a stand-in for `mysql.rds_set_configuration`.
- Oracle Free 23 on port 31521, a CDB with the `FREEPDB1` pluggable database.
  `oracle-init.sh` makes it look like RDS for Oracle: ARCHIVELOG and
  supplemental logging on, an `ADMIN` user in the PDB (like the RDS master
  user), and a stand-in `rdsadmin.rdsadmin_util`. Its `grant_sys_object` runs
  a plain `GRANT`, and `set_configuration` does nothing.
- Kafka 4.1 on port 9092, one node, `PLAINTEXT`.

## Tests

- `test_mariadb`: creates the CDC user and checks its grants with
  `SHOW GRANTS`. Then it changes the password parameter and checks that the
  login check fails, without printing the password.
- `test_oracle`: the same for Oracle, on the PDB. It checks the system
  privileges and the SYS object grants in `DBA_SYS_PRIVS` and
  `DBA_TAB_PRIVS`.
- `test_kafka`: creates two topics and checks that they exist.
- `test_kafka_unreachable_cluster_fails`: an unreachable broker gives exit
  code 1 and a clear message.

Each test uses new user and topic names, so the tests also pass against
services that already ran other tests.

## Not covered

- MSK IAM authentication (`SASL_SSL`).
- The real RDS procedures (`rdsadmin`, `mysql.rds_set_configuration`).
- RDS for Oracle CDB grants.

Test these in AWS.

The bundler skips `tests` folders, so these files are not in the bundles or
the runner image.
