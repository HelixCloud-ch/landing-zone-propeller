# CDC Prepare Oracle

> **Unverified against real infrastructure.** This project is designed and
> offline-tested like `cdc-prepare-mariadb`, but nothing here has been run
> against a live Oracle instance. Do not use it in production before completing
> the checks in
> [`docs/cdc-deployment-verification.md`](../../../docs/cdc-deployment-verification.md#oracle)
> — in particular, measuring LogMiner's CPU impact on the source instance,
> which cannot be assessed offline and is marked blocking there.

Idempotently prepares an Oracle source database for Debezium CDC via
LogMiner. This is a non-Terraform, `just`-driven project with no Terraform
state; all work lives in `prepare.py`. Structurally it mirrors
[`cdc-prepare-mariadb`](../cdc-prepare-mariadb/README.md) — same input/output
shape, same idempotency guarantees, same client-boundary testing pattern —
adapted for Oracle's LogMiner preconditions and grant model.

It verifies the LogMiner preconditions **before** making any change, creates a
least-privilege CDC user with the grants Debezium's own documentation lists
for its LogMiner adapter, and resolves the CDC credential from **two** named
scalar `SecureString` SSM parameters — one for the username, one for the
password. Every environment-specific value — host, service/PDB name, user,
parameter names, KMS key — arrives as a `PROPELLER_INPUT_*` variable; nothing
is hardcoded.

## What it does

On `apply`, `prepare.py` runs the following ordered, idempotent flow:

1. Reads the administrative credential from the SSM parameter *named* by an
   input (see [Admin credential forms](#admin-credential-forms), identical to
   `cdc-prepare-mariadb`'s).
2. Resolves the CDC credential from the two parameters *named* by
   `cdc_username_parameter` and `cdc_password_parameter` (see
   [Credential handling](#credential-handling), identical to
   `cdc-prepare-mariadb`'s): reads each if it already exists, or creates it —
   the username from the `cdc_username` input, the password freshly generated —
   if it does not.
3. Verifies the LogMiner preconditions on the source database — `ARCHIVELOG`
   mode, minimal supplemental logging, and primary-key supplemental logging —
   from a single `V_$DATABASE` query. If any fails, it aborts naming the
   offending setting **before touching anything**.
4. Creates the CDC user (`CREATE USER`, using the resolved credential; Oracle
   has no `IF NOT EXISTS` form, so this step is skipped entirely when the
   account already exists) and grants it the privileges Debezium's LogMiner
   adapter requires (see [The grant list](#the-grant-list)).
5. On first creation of the database account only, sets the archive-log
   retention window via `rdsadmin.rdsadmin_util.set_configuration
   ('archivelog retention hours', ...)`.

## The grant list

The exact grant list was **never verified during the original research** for
this framework, and an earlier draft based on AWS DMS's Oracle privilege
requirements was explicitly flagged as not to be trusted as authoritative — it
approximates what DMS's Binary Reader/LogMiner needs, not what Debezium's own
LogMiner adapter needs, and the two are different products with different
privilege surfaces. This project's grant list instead comes from two primary
sources, cross-referenced against each other:

- **What to grant** — Debezium's own
  [Configuration of the connector's Oracle user account](https://docs.redhat.com/ko/documentation/red_hat_build_of_debezium/3.2.7/html/debezium_user_guide/configuration-of-the-connectors-oracle-user-account)
  — the LogMiner adapter's documented privilege list, with the reason for
  each grant.
- **How to grant it on RDS** — AWS's
  [Granting SELECT or EXECUTE privileges to SYS objects](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.Oracle.CommonDBATasks.TransferPrivileges.html)
  — on RDS for Oracle the master user is not real `SYS`, so a privilege on a
  `SYS`-owned package (`DBMS_LOGMNR`, `DBMS_LOGMNR_D`) or a `V_$` dynamic view
  cannot be granted with a plain `GRANT`; it fails with `ORA-01031`. It must be
  transferred via `rdsadmin.rdsadmin_util.grant_sys_object` instead.

The list splits into two Terraform-module-style groups for exactly that
reason:

| Group | Mechanism | Members |
| ----- | --------- | ------- |
| `CDC_SYSTEM_GRANTS` | plain `GRANT ... TO <user>` | `CREATE SESSION`, `SELECT ANY TABLE`, `FLASHBACK ANY TABLE`, `SELECT ANY TRANSACTION`, `SELECT_CATALOG_ROLE`, `EXECUTE_CATALOG_ROLE`, `LOGMINING`, `CREATE TABLE`, `LOCK ANY TABLE`, `CREATE SEQUENCE` |
| `CDC_SYS_OBJECT_GRANTS` | `rdsadmin.rdsadmin_util.grant_sys_object` | `EXECUTE` on `DBMS_LOGMNR`, `DBMS_LOGMNR_D`; `SELECT` on `V_$DATABASE`, `V_$LOG`, `V_$LOG_HISTORY`, `V_$LOGMNR_LOGS`, `V_$LOGMNR_CONTENTS`, `V_$LOGMNR_PARAMETERS`, `V_$LOGFILE`, `V_$ARCHIVED_LOG`, `V_$ARCHIVE_DEST_STATUS`, `V_$TRANSACTION` |

Both groups are re-issued on every `apply`, converging a partially-prepared
account — a plain `GRANT` of an already-held privilege is a no-op, and AWS's
own documentation for `grant_sys_object` states that re-granting an
already-granted privilege succeeds.

**A known open risk, not yet resolved:** at least one report from the
Debezium community describes `ORA-01031` errors on RDS for Oracle CDB
instances specifically, even after granting everything above, because the
root-container-level privileges Debezium's connector needs in a multitenant
(CDB) configuration cannot be granted the same way on RDS as on a self-managed
Oracle instance. This project has not been run against a real RDS for Oracle
CDB instance, so whether this grant list is sufficient in that configuration
is unconfirmed — see
[`docs/cdc-deployment-verification.md`](../../../docs/cdc-deployment-verification.md#oracle).

**Container clause.** Debezium's own example issues every grant with
`CONTAINER=ALL` on a genuine multitenant (CDB) database and additionally
grants `SET CONTAINER`. This project's grant statements deliberately do
**not** include a container clause, because whether one is valid — and which
form — depends on RDS for Oracle's specific CDB configuration (multi-tenant
vs. single-tenant vs. non-CDB; see
[RDS for Oracle database architecture](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/oracle-multi-architecture.html)),
which this project has not been run against. Confirm the correct grant form
for the target configuration during the deployment-verification pass before
relying on this project's grants as written.

## Runner

Requires the **In_VPC_Runner**, because it must reach the source database and
Parameter Store **inside the VPC**. It makes no IAM calls — the only AWS API
it uses is SSM `GetParameter`/`PutParameter`, so it needs no elevated role,
only in-VPC reachability to the database endpoint and to the Parameter Store
VPC endpoint.

It depends on the `oracledb` and `boto3` libraries being baked into the
deploy-runner image (see `platform/projects/deploy-runner-image/`), because an
In_VPC_Runner has no internet access to install them at run time. `oracledb`
runs in **thin mode** by default — this project never calls
`oracledb.init_oracle_client()` — so it needs no Oracle Instant Client and
introduces no component under Oracle's OTN license.

## Pipeline wiring

```yaml
stages:
  - name: cdc-prepare
    steps:
      - project: cdc-prepare-oracle
        target: workload-account
        runner: in-vpc
        inputs:
          - name: rds-oracle.endpoint_address
            var: db_host
          - name: rds-oracle.db_name
            var: service_name
          - name: cdc-config.pdb_name
            var: pdb_name
          - name: rds-oracle.admin_credential_parameter_name
            var: admin_credential_parameter
          - name: cdc-config.cdc_username
            var: cdc_username
          - name: cdc-config.cdc_username_parameter
            var: cdc_username_parameter
          - name: cdc-config.cdc_password_parameter
            var: cdc_password_parameter
          - name: cdc-config.archivelog_retention_hours
            var: archivelog_retention_hours
```

The two parameter names written here (`cdc_username_parameter` and
`cdc_password_parameter`) are the same names the downstream
`msk-connect-debezium` connector project reads to configure its source
credential — one `${ssm::…}` reference each for `database.user` and
`database.password`, identical convention to `cdc-prepare-mariadb` (see
[Outputs](#outputs)).

## Inputs

Inputs arrive as `PROPELLER_INPUT_*` environment variables.

| Input | Required | Meaning |
| ----- | :------: | ------- |
| `PROPELLER_INPUT_db_host` | yes | Source Oracle endpoint hostname. |
| `PROPELLER_INPUT_db_port` | no | Source port. Default `1521`. |
| `PROPELLER_INPUT_service_name` | yes | Oracle service name / SID to connect to. On a CDB instance this is the container database's service. |
| `PROPELLER_INPUT_pdb_name` | no | Pluggable database (RDS "tenant database") to connect to instead of `service_name`. Empty (default) means non-CDB, or connect at the container level. |
| `PROPELLER_INPUT_admin_credential_parameter` | yes | **Name** of the SSM parameter holding the admin credential used to connect (never a hardcoded path). See [Admin credential forms](#admin-credential-forms). |
| `PROPELLER_INPUT_cdc_username` | yes | Bare Oracle identifier of the CDC user to create (`[A-Za-z][A-Za-z0-9_#$]{0,29}`, Oracle's unquoted-identifier grammar). Used only when `cdc_username_parameter` does not yet exist — see [Credential handling](#credential-handling). |
| `PROPELLER_INPUT_cdc_username_parameter` | yes | **Name** of the SSM parameter holding the CDC user's username. Source of truth if it already exists; created (from `cdc_username`) if it does not. See [Credential handling](#credential-handling). |
| `PROPELLER_INPUT_cdc_password_parameter` | yes | **Name** of the SSM parameter holding the CDC user's password. Source of truth if it already exists; created (freshly generated) if it does not. See [Credential handling](#credential-handling). |
| `PROPELLER_INPUT_archivelog_retention_hours` | no | Hours to retain archived redo logs, set via `rdsadmin.rdsadmin_util.set_configuration` **on first creation of the database account only**. Default `24`. |
| `PROPELLER_INPUT_kms_key_id` | no | KMS key encrypting the parameter, if this project creates it. Default `alias/aws/ssm` (the AWS-managed SSM key). |

## Admin credential forms

Identical contract to `cdc-prepare-mariadb`: `admin_credential_parameter`
names an SSM parameter whose value the project reads to obtain the login it
connects with. `read_admin_credential` accepts a **JSON document**
(`{"username": "...", "password": "..."}`) or a **scalar password** (the
value is the password itself; the username is then taken from the
`cdc_username` input). A value that parses as JSON but is not an object with
both keys is treated as the scalar-password form. The credential value is
never logged or echoed.

## Credential handling

Identical contract to `cdc-prepare-mariadb`. The CDC user's credential lives in
**two separate scalar `SecureString` parameters** — `cdc_username_parameter`
holds the username, `cdc_password_parameter` holds the password. Each is a
whole, verbatim value, **not** a key inside a JSON document. Each is resolved
independently and is its own **source of truth**:

- **If a parameter already exists**, its stored scalar value is read with
  decryption and used as-is. This project **never overwrites an existing
  value.**
- **If a parameter does not exist**, it is **created** as a scalar
  `SecureString` encrypted with `kms_key_id`: the username parameter from the
  `cdc_username` input, the password parameter from a freshly generated
  password (`secrets.token_urlsafe(32)`).

A partially-provisioned state (only one of the two parameters present) is
handled correctly — the existing one is read, only the missing one is created.

**Why two scalar parameters, not one JSON document.** The downstream
`msk-connect-debezium` connector reads each value with the AWS MSK Connect SSM
Config_Provider, referencing it as `${ssm::<parameter-name>}`. That provider
resolves the placeholder to the parameter's **entire value** and **cannot
extract a key out of a JSON document** — only the Secrets Manager provider can.
A scalar-per-value shape is therefore the only one the connector's
`database.user` / `database.password` read path accepts. See the
[shared module README](../../shared/modules/msk-connect-debezium/README.md) and
[Tutorial: Externalizing sensitive information using config providers](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-config-provider.html).

**There is no rotation.** This project does not change a parameter once it
exists, and does not accept a version or "bump to rotate" input. To change the
CDC user's password, either update the password parameter directly (and
separately update the database account, e.g. via `ALTER USER ... IDENTIFIED
BY`) or manage the credential from a dedicated project built for that purpose.

## Outputs

Writes to **SSM parameters**, not a propeller output field — same convention
as `cdc-prepare-mariadb`. It writes the CDC username and password, each as a
scalar `SecureString`, at the parameters named by `cdc_username_parameter` and
`cdc_password_parameter` — but only when a parameter does not already exist
(see [Credential handling](#credential-handling)). The connector reads each
directly with the SSM Config_Provider — one `${ssm::…}` reference each for
`database.user` and `database.password`, no extraction step required. It emits
**no credential value** anywhere — not to stdout, not to stderr, and not to a
`.propeller-outputs` file.

## Idempotency and destroy

Re-running is safe:

- **No `CREATE USER` on a re-run.** Oracle has no `IF NOT EXISTS` form of
  `CREATE USER`, so the existence check runs first and the statement is
  skipped entirely — never issued and allowed to fail — when the account
  already exists.
- **The credential parameters are never overwritten.** Each is created only
  when absent (see [Credential handling](#credential-handling)); an existing
  parameter is read and left exactly as it is, on every run.
- **Grants are idempotent and always re-issued**, to converge a
  partially-prepared account. A plain `GRANT` of an already-held privilege is
  a no-op; AWS documents that re-calling `grant_sys_object` for an
  already-granted privilege succeeds.
- **The archive-log retention window is set only on first creation of the
  database account.** Unlike the grants, this is deliberately *not*
  re-applied on every run — a re-run must not silently override a retention
  value an operator has since tuned to a different number for reasons this
  project has no visibility into.
- **`destroy` is a deliberate no-op.** It does **not** drop the CDC user, for
  the same reason as `cdc-prepare-mariadb`: dropping the user is irreversible
  and is an operator decision, not the deployment's.

## Preconditions

The project verifies all of the following **before any modification**,
reading a single row from `V_$DATABASE`, and aborts naming the offending
setting if a check fails:

- **`ARCHIVELOG` mode** (`LOG_MODE = 'ARCHIVELOG'`). On RDS for Oracle,
  archive logging is a side effect of setting the instance's automated-backup
  retention period (`backup_retention_period`) to a non-zero value —
  **RDS for Oracle generates NO archived redo logs at all with zero backup
  retention**, so this prerequisite is absolute, not advisory. A failure here
  names that control rather than a setting the operator cannot change
  directly with SQL.
- **Minimal supplemental logging** (`SUPPLEMENTAL_LOG_DATA_MIN = 'YES'`),
  enabled via `rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD')`.
  Without it, LogMiner cannot reconstruct row changes from the redo stream at
  all.
- **Primary-key supplemental logging**
  (`SUPPLEMENTAL_LOG_DATA_PK = 'YES'`), enabled via
  `rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD', 'PRIMARY KEY')`.
  Without it, an `UPDATE`/`DELETE` redo record may not carry enough of the
  old row's key to identify which row changed.

Because the check runs first and reads only, a precondition failure leaves
the database untouched. Setting up supplemental logging and archive log
retention are themselves database-owner actions this project does **not**
perform — see [What does NOT belong here](#what-does-not-belong-here).

## LogMiner strategy — a note for `msk-connect-debezium`, not this project

This project prepares the *database*; the LogMiner *mining strategy*
(`log.mining.strategy`) is a connector-configuration property set by the
shared `msk-connect-debezium` module's `config/oracle.tftpl`, not by anything
here. It is called out in this README because the strategy choice interacts
with what this project's preconditions verify: `hybrid` (the strategy the
module template uses) needs no extra archive-log volume beyond ordinary
`ARCHIVELOG` mode, whereas the deprecated `redo_log_catalog` strategy would
additionally write the data dictionary into the online redo logs, generating
materially more archive log volume than this project's precondition check
accounts for. See the shared module's README for the full tradeoff.

## What does NOT belong here

- **Setting up archive log retention or supplemental logging from scratch** —
  this project only *verifies* they are already correctly configured (see
  [Preconditions](#preconditions)); enabling them in the first place is a
  database/instance-configuration decision the consumer makes before running
  this project, the same boundary `cdc-prepare-mariadb` draws around binary
  logging.
- **Any Oracle parameter-group change.** LogMiner (the adapter this project
  and the shared module use) needs no `ENABLE_GOLDENGATE_REPLICATION` or other
  parameter-group setting — that parameter is specific to Oracle XStream,
  which this framework does not use. Everything LogMiner needs is set via
  SQL/`rdsadmin_util` procedures, which is exactly what this project does — so
  the LogMiner path needs no change to `rds-oracle`'s parameter-group
  forwarding.
- **Creating Kafka topics** — that is `cdc-topics`.
- **Creating the connector or its IAM role** — that is `msk-connect-debezium`.
- **Dropping the CDC user** — `destroy` is intentionally a no-op; user
  removal is a manual operator decision.
- **Password rotation** — this project fills in the credential parameter only
  when it is absent; it never changes an existing one. Rotating the CDC
  user's password is out of scope here.
- **Secrets Manager support** — the credential parameter is SSM
  `SecureString` only today. Supporting Secrets Manager as an alternative
  backend is a planned future addition, not implemented in this version.

## Standalone invocation

The project runs standalone through `just` with the inputs supplied as
environment variables. The complete input set:

```bash
export PROPELLER_INPUT_db_host=my-oracle.example.internal          # required
export PROPELLER_INPUT_db_port=1521                                # optional (default)
export PROPELLER_INPUT_service_name=ORCLCDB                        # required
export PROPELLER_INPUT_pdb_name=ORCLPDB1                           # optional (empty = non-CDB)
export PROPELLER_INPUT_admin_credential_parameter=/rds/admin       # required (NAME)
export PROPELLER_INPUT_cdc_username=CDC_USER                       # required (used only if the username param below is absent)
export PROPELLER_INPUT_cdc_username_parameter=/cdc/username        # required (NAME; source of truth if present)
export PROPELLER_INPUT_cdc_password_parameter=/cdc/password        # required (NAME; source of truth if present)
export PROPELLER_INPUT_archivelog_retention_hours=24               # optional (default)
export PROPELLER_INPUT_kms_key_id=alias/aws/ssm                    # optional (default)

just plan     # report intent only; contacts nothing, modifies nothing
just apply    # verify preconditions, create/grant the CDC user, publish credential
just destroy  # no-op (does NOT drop the CDC user)
```

`apply` must run on an In_VPC_Runner able to reach the database and Parameter
Store. `plan` echoes only host, service/PDB name, user, and parameter
*names* — never a credential value.

## Sleep/wake and teardown

No sleep/wake recipe is implemented for any CDC project. Implementing sleep
modes is the pipeline consumer's decision; these projects document the
constraints only. The constraints below concern the CDC chain as a whole and
are repeated on every CDC project's README so the ordering is visible
wherever an operator starts:

- The connector must be removed **before** its source database and its
  Kafka cluster.
- Under the framework's MSK sleep semantics (destroy-only), a sleeping cluster
  loses its topics and consumer offsets, so on wake the Topics project must run
  again before the Connector, and Debezium then
  performs a recovery snapshot.
- A sleep outlasting the configured archive-log retention window turns a CDC
  gap into a full re-snapshot — Oracle's equivalent of MariaDB's binlog
  retention constraint.

## References

- [Debezium connector for Oracle](https://debezium.io/documentation/reference/stable/connectors/oracle.html)
- [Configuration of the connector's Oracle user account](https://docs.redhat.com/ko/documentation/red_hat_build_of_debezium/3.2.7/html/debezium_user_guide/configuration-of-the-connectors-oracle-user-account)
- [Granting SELECT or EXECUTE privileges to SYS objects (RDS)](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.Oracle.CommonDBATasks.TransferPrivileges.html)
- [Retaining archived redo logs (RDS)](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.Oracle.CommonDBATasks.RetainRedoLogs.html)
- [Using an Oracle database as a source for AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.Oracle.html) — supplemental-logging setup steps, cited for the `rdsadmin_util.alter_supplemental_logging` calls; DMS's own *privilege list* is a different product's requirements and is not the source for this project's grants (see [The grant list](#the-grant-list)).
- [RDS for Oracle database architecture](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/oracle-multi-architecture.html) — CDB/PDB configurations.
- [python-oracledb — thin mode](https://python-oracledb.readthedocs.io/en/latest/user_guide/initialization.html)
- [MSK Connect — Externalizing sensitive information using config providers](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-config-provider.html) — why the connector needs two scalar parameters, not one JSON document.
