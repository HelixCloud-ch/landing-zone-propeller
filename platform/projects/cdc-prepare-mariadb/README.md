# CDC Prepare MariaDB

Idempotently prepares a MariaDB source database for Debezium CDC. This is a
non-Terraform, `just`-driven project with no Terraform state; all work lives in
`prepare.py`.

It verifies the binary-logging preconditions **before** making any change,
creates a least-privilege CDC user with exactly five grants, sets the
binary-log retention window, and resolves the CDC credential from **two**
named scalar `SecureString` SSM parameters — one for the username, one for the
password. Every environment-specific value — host, user, parameter names, KMS
key — arrives as a `PROPELLER_INPUT_*` variable; nothing is hardcoded.

## What it does

On `apply`, `prepare.py` runs the following ordered, idempotent flow:

1. Reads the administrative credential from the SSM parameter *named* by an
   input (see [Admin credential forms](#admin-credential-forms) below).
2. Resolves the CDC credential from the two parameters *named* by
   `cdc_username_parameter` and `cdc_password_parameter` (see
   [Credential handling](#credential-handling) below): reads each if it already
   exists, or creates it — the username from the `cdc_username` input, the
   password freshly generated — if it does not.
3. Verifies the binary-logging preconditions on the source database. If any
   fails, it aborts naming the offending setting **before touching anything**.
4. Creates the CDC user (`CREATE USER IF NOT EXISTS`, using the resolved
   credential) and grants it exactly the five privileges Debezium requires:
   `SELECT`, `RELOAD`, `SHOW DATABASES`, `REPLICATION SLAVE`,
   `REPLICATION CLIENT`.
5. Sets the binary-log retention window via
   `mysql.rds_set_configuration('binlog retention hours', ...)`.

## Runner

Requires the **In_VPC_Runner**, because it must reach the source database and
Parameter Store **inside the VPC**. It makes no IAM calls — the only AWS API it
uses is SSM `GetParameter`/`PutParameter`, so it needs no elevated role, only
in-VPC reachability to the database endpoint and to the Parameter Store VPC
endpoint.

It also depends on the `PyMySQL` and `boto3` libraries being baked into the
deploy-runner image (see `platform/projects/deploy-runner-image/`), because an
In_VPC_Runner has no internet access to install them at run time.

## Pipeline wiring

```yaml
stages:
  - name: cdc-prepare
    steps:
      - project: cdc-prepare-mariadb
        target: workload-account
        runner: in-vpc
        inputs:
          - name: rds-mariadb.endpoint_address
            var: db_host
          - name: rds-mariadb.admin_credential_parameter_name
            var: admin_credential_parameter
          - name: cdc-config.cdc_username
            var: cdc_username
          - name: cdc-config.cdc_username_parameter
            var: cdc_username_parameter
          - name: cdc-config.cdc_password_parameter
            var: cdc_password_parameter
          - name: cdc-config.binlog_retention_hours
            var: binlog_retention_hours
```

The two parameter names written here (`cdc_username_parameter` and
`cdc_password_parameter`) are the same names the downstream
`msk-connect-debezium` connector project reads to configure its source
credential — one `${ssm::…}` reference each for `database.user` and
`database.password` (see [Outputs](#outputs)).

## Inputs

Inputs arrive as `PROPELLER_INPUT_*` environment variables.

| Input | Required | Meaning |
| ----- | :------: | ------- |
| `PROPELLER_INPUT_db_host` | yes | Source MariaDB endpoint hostname. |
| `PROPELLER_INPUT_db_port` | no | Source port. Default `3306`. |
| `PROPELLER_INPUT_admin_credential_parameter` | yes | **Name** of the SSM parameter holding the admin credential used to connect (never a hardcoded path). See [Admin credential forms](#admin-credential-forms). |
| `PROPELLER_INPUT_cdc_username` | yes | Bare identifier of the CDC user to create (`[A-Za-z0-9_]` only). Used only when `cdc_username_parameter` does not yet exist — see [Credential handling](#credential-handling). |
| `PROPELLER_INPUT_cdc_username_parameter` | yes | **Name** of the SSM parameter holding the CDC user's username. Source of truth if it already exists; created (from `cdc_username`) if it does not. See [Credential handling](#credential-handling). |
| `PROPELLER_INPUT_cdc_password_parameter` | yes | **Name** of the SSM parameter holding the CDC user's password. Source of truth if it already exists; created (freshly generated) if it does not. See [Credential handling](#credential-handling). |
| `PROPELLER_INPUT_binlog_retention_hours` | yes | Hours to retain binary logs, set via `mysql.rds_set_configuration`. |
| `PROPELLER_INPUT_kms_key_id` | no | KMS key encrypting the parameter, if this project creates it. Default `alias/aws/ssm` (the AWS-managed SSM key). |

## Admin credential forms

The `admin_credential_parameter` input names an SSM parameter whose value the
project reads to obtain the login it connects with. `read_admin_credential`
accepts **two forms**, so it works with either credential convention a consumer
already uses:

- **JSON document** — the parameter value is a JSON object carrying both keys,
  `{"username": "...", "password": "..."}`. Both fields are taken from the
  document. Use this when the admin username is stored alongside its password.
- **Scalar password** — the parameter value is the password itself (any value
  that is not a JSON object with both keys). The username is then taken from the
  `cdc_username` input. Use this when only the password is stored and the admin
  username is fixed by convention.

A value that parses as JSON but is not an object with both `username` and
`password` (a bare string, a number, or a dict missing a key) is treated as the
scalar-password form. The credential value is never logged or echoed.

## Credential handling

The CDC user's credential lives in **two separate scalar `SecureString`
parameters** — `cdc_username_parameter` holds the username, and
`cdc_password_parameter` holds the password. Each is a whole, verbatim value,
**not** a key inside a JSON document. Each parameter is resolved
independently, and each is its own **source of truth**:

- **If a parameter already exists**, its stored scalar value is read with
  decryption and used as-is. This project **never overwrites an existing
  value.**
- **If a parameter does not exist**, it is **created** as a scalar
  `SecureString` encrypted with `kms_key_id`: the username parameter from the
  `cdc_username` input, the password parameter from a freshly generated
  password (`secrets.token_urlsafe(32)`).

Because the two are resolved independently, a partially-provisioned state
(only the username parameter present, or only the password parameter present)
is handled correctly — the existing one is read, and only the missing one is
created.

**Why two scalar parameters, not one JSON document.** The downstream
`msk-connect-debezium` connector reads each value with the AWS MSK Connect
SSM Config_Provider, referencing it as `${ssm::<parameter-name>}` in the
connector configuration. That provider resolves the placeholder to the
parameter's **entire value** and **cannot extract a key out of a JSON
document** — only the Secrets Manager provider can. A scalar-per-value shape
is therefore the only one the connector's `database.user` / `database.password`
read path accepts. See the
[shared module README](../../shared/modules/msk-connect-debezium/README.md)
and
[Tutorial: Externalizing sensitive information using config providers](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-config-provider.html).

**There is no rotation.** This project does not change a parameter once it
exists, and does not accept a version or "bump to rotate" input. To change the
CDC user's password, either update the password parameter directly (and
separately update the database account, e.g. via `ALTER USER ... IDENTIFIED
BY`) or manage the credential from a dedicated project built for that purpose
— this project's only job is to make sure the parameters are filled in.

## Outputs

This project writes to **SSM parameters**, not a propeller output field: the
CDC username and password, each as a scalar `SecureString`, at the parameters
named by `cdc_username_parameter` and `cdc_password_parameter` — but only when
a parameter does not already exist (see
[Credential handling](#credential-handling)). The consumer supplied those names
as inputs, and the same names are what the `msk-connect-debezium` connector
project reads directly with the SSM Config_Provider — one `${ssm::…}` reference
each for `database.user` and `database.password`, no extraction step required.

It deliberately emits **no credential value** anywhere — not to stdout, not to
stderr, and not to a `.propeller-outputs` file. The only cross-project contract
is the two parameter *names*, which the consumer already knows because it chose
them.

## Idempotency and destroy

Re-running is safe:

- **No `CREATE USER` on a re-run.** The user is created only when it does not
  already exist. On a re-run the existing account is left in place.
- **The credential parameters are never overwritten.** Each is created only
  when absent (see [Credential handling](#credential-handling)); an existing
  parameter is read and left exactly as it is, on every run.
- **`GRANT` and retention are idempotent.** They are re-issued on every run to
  converge a partially-prepared account, with no side effect when already set.
- **`destroy` is a deliberate no-op.** It does **not** drop the CDC user.
  Dropping the user is irreversible and is an operator decision, not the
  deployment's — remove it manually if genuinely required.

## Preconditions

The project verifies all of the following **before any modification**, and
aborts naming the offending setting if a check fails:

- **Binary logging active** (`log_bin = ON`). On RDS MariaDB this is enabled by
  setting the instance's automated-backup retention period
  (`backup_retention_period`) to a non-zero value — a failure here names that
  control rather than a server variable the operator cannot set directly.
- **`binlog_format = ROW`.**
- **`binlog_row_image = FULL`.**
- **`log_bin_compress` off** — Debezium cannot read a compressed binary log.
  When the server does not expose the variable at all, its absence is treated as
  not-enabled; only a present-and-`ON` value fails.

Because the checks run first and read only, a precondition failure leaves the
database untouched.

## Standalone invocation

The project runs standalone through `just` with the inputs supplied as
environment variables. The complete input set:

```bash
export PROPELLER_INPUT_db_host=my-db.example.internal              # required
export PROPELLER_INPUT_db_port=3306                                # optional (default)
export PROPELLER_INPUT_admin_credential_parameter=/rds/admin       # required (NAME)
export PROPELLER_INPUT_cdc_username=cdc_user                       # required (used only if the username param below is absent)
export PROPELLER_INPUT_cdc_username_parameter=/cdc/username        # required (NAME; source of truth if present)
export PROPELLER_INPUT_cdc_password_parameter=/cdc/password        # required (NAME; source of truth if present)
export PROPELLER_INPUT_binlog_retention_hours=168                  # required
export PROPELLER_INPUT_kms_key_id=alias/aws/ssm                    # optional (default)

just plan     # report intent only; contacts nothing, modifies nothing
just apply    # verify preconditions, create/grant the CDC user, publish credential
just destroy  # no-op (does NOT drop the CDC user)
```

`apply` must run on an In_VPC_Runner able to reach the database and Parameter
Store. `plan` echoes only host, user, and parameter *names* — never a credential
value.

## Sleep/wake and teardown

No sleep/wake recipe is implemented for any CDC project. Implementing sleep
modes is the pipeline consumer's decision; these projects document the
constraints only. The constraints below concern the CDC chain as a whole and are
repeated on every CDC project's README so the ordering is visible wherever an
operator starts:

- The connector must be removed **before** its source database and its Kafka
  cluster.
- Under the framework's MSK sleep semantics (destroy-only), a sleeping cluster
  loses its topics and consumer offsets, so on wake the Topics project must run
  again before the Connector, and Debezium then performs a recovery
  snapshot.
- A sleep outlasting the configured binary-log retention window turns a CDC gap
  into a full re-snapshot.

## What does NOT belong here

- **Creating Kafka topics** — that is `cdc-topics`.
- **Creating the connector or its IAM role** — that is `msk-connect-debezium`.
- **Dropping the CDC user** — `destroy` is intentionally a no-op; user removal is
  a manual operator decision.
- **Password rotation** — this project fills in the credential parameter only
  when it is absent; it never changes an existing one. Rotating the CDC user's
  password is out of scope here.
- **Secrets Manager support** — the credential parameter is SSM `SecureString`
  only today. Supporting Secrets Manager as an alternative backend is a
  planned future addition, not implemented in this version.

## References

- [Debezium 2.7 — MariaDB connector](https://debezium.io/documentation/reference/2.7/connectors/mariadb.html)
- [Amazon RDS — MariaDB binary logging format](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.MariaDB.BinaryFormat.html)
- [Amazon RDS — `mysql.rds_set_configuration` (binlog retention hours)](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/mysql_rds_set_configuration.html)
- [AWS Systems Manager — Parameter Store `SecureString` parameters](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [MSK Connect — Externalizing sensitive information using config providers](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-config-provider.html) — why the connector needs two scalar parameters, not one JSON document.
