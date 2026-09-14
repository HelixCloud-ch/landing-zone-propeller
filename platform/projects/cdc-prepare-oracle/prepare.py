#!/usr/bin/env python3
"""Prepare an Oracle source database for Debezium CDC via LogMiner.

Idempotent, re-runnable preparation of one Oracle instance (RDS for Oracle):

1. Read inputs from the environment (``PROPELLER_INPUT_*``).
2. Read the administrative credential from the SSM parameter *named* by an
   input (never a hardcoded path).
3. Verify LogMiner preconditions BEFORE making any modification: ARCHIVELOG
   mode and database-level supplemental logging (minimal + primary key).
4. Create a least-privilege ``CDC_User`` with the grants Debezium's LogMiner
   adapter documents as required, resolve its credential from TWO separate,
   named SSM ``SecureString`` parameters — one for the username, one for the
   password (each a source of truth if present, created if absent — no
   rotation, see ``resolve_cdc_credential``), and — on first creation only —
   set the archive-log retention window via
   ``rdsadmin.rdsadmin_util.set_configuration``.

   Two SCALAR parameters (not one JSON document) are used deliberately: the
   downstream ``msk-connect-debezium`` connector reads each with the SSM
   Config_Provider (``$${ssm::<name>}``), which resolves a placeholder to the
   parameter's whole value and cannot extract a key out of a JSON document.
   See the module README and the project README's "Credential handling".

Phase 2 / unverified against real infrastructure (see the spec's tasks.md and
`docs/cdc-deployment-verification.md`). The grant list below is sourced from
two primary references, not from the DMS-derived approximation that was
sitting in the research notes and is explicitly NOT to be trusted (task 2.1):

- Debezium's own "Configuration of the connector's Oracle user account"
  (https://docs.redhat.com/ko/documentation/red_hat_build_of_debezium/3.2.7/html/debezium_user_guide/configuration-of-the-connectors-oracle-user-account)
  — the *what*: which privileges LogMiner needs and why.
- AWS's RDS documentation for `grant_sys_object`
  (https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.Oracle.CommonDBATasks.TransferPrivileges.html)
  — the *how* on RDS: the master user is not real SYS, so any privilege on a
  SYS-owned object (a package, or a `V_$` dynamic view) must be transferred via
  `rdsadmin.rdsadmin_util.grant_sys_object` rather than a plain GRANT.

Nothing about the host, user, parameter names, account or region is hardcoded;
every environment-specific value arrives as a ``PROPELLER_INPUT_*`` variable.
This project requires no AWS access to *build* or test — it is exercised
entirely through mocked clients (see the project tests) — but at run time it
must execute on an In_VPC_Runner able to reach the database and Parameter
Store.

A credential VALUE is never written to stdout, stderr, or any output.

Implementation note: the AWS (boto3 SSM) and database (python-oracledb thin
mode) clients are constructed in exactly one place — :func:`build_clients` —
so that tests can mock at the client boundary (design.md, Testing Strategy).
The rest of the module receives already-constructed clients and never imports
boto3 or oracledb at call sites. This mirrors cdc-prepare-mariadb/prepare.py's
structure deliberately, so the two projects read the same way.

Oracle DDL cannot bind ANY variable — not even values, unlike MariaDB where
only the account identifier was grammar-forced out of parameterisation. Every
statement this module issues that carries an input-derived value (the CDC
username, the password, the retention hours) is therefore built through
:func:`_validated_identifier` / :func:`_quoted_literal`, never through a
driver-level bind, and every such value is validated or escaped before it is
composed. See ``run_ddl`` for the single place this composition happens.
"""

from __future__ import annotations

import json
import os
import re
import secrets
import sys
from dataclasses import dataclass
from typing import Any, Callable

# Default KMS key used to encrypt the CDC credential parameters when no
# kms_key_id input is supplied: the AWS-managed SSM key.
DEFAULT_KMS_KEY_ID = "alias/aws/ssm"

# Note on the credential shape: the CDC username and password are stored in TWO
# separate scalar SecureString parameters, not one JSON document. The connector
# reads each via the SSM Config_Provider, which cannot extract a key out of JSON
# (see module docstring). read_admin_credential below still accepts a JSON
# document OR a scalar because the ADMIN credential is read, not written by this
# project, and consumers store it either way — a different contract from the two
# scalar parameters this project creates for the CDC user.

# Every environment-specific value arrives as a PROPELLER_INPUT_* variable. The
# prefix is defined once here so the reader never spells it inline.
INPUT_PREFIX = "PROPELLER_INPUT_"

# Default Oracle listener port used when the db_port input is not supplied.
DEFAULT_DB_PORT = 1521

# Default archive-log retention window (hours) used when the input is not
# supplied. 24h mirrors the AWS documentation examples for this procedure.
DEFAULT_ARCHIVELOG_RETENTION_HOURS = 24

# ── The LogMiner grant list ────────────────────────────────────────────────────
#
# Split into two groups because RDS grants them two different ways:
#
# - CDC_SYSTEM_GRANTS are ordinary system privileges/roles. The RDS master user
#   already holds these (directly or WITH ADMIN OPTION on the role) and can
#   GRANT them with a plain statement.
# - CDC_SYS_OBJECT_GRANTS are privileges on SYS-owned packages and V_$ dynamic
#   views. On RDS the master user is not real SYS, so these can only be
#   transferred via rdsadmin.rdsadmin_util.grant_sys_object — a plain GRANT on
#   one of these objects fails with ORA-01031 (insufficient privileges).
#
# Source: Debezium's "Configuration of the connector's Oracle user account"
# (see module docstring). CONTAINER=ALL / SET CONTAINER are read from
# inputs.pdb_name being set (CDB architecture) rather than hardcoded, because
# RDS for Oracle's non-CDB and single/multi-tenant CDB configurations differ
# in whether a container clause is even valid.
CDC_SYSTEM_GRANTS = (
    "CREATE SESSION",
    "SELECT ANY TABLE",
    "FLASHBACK ANY TABLE",
    "SELECT ANY TRANSACTION",
    "SELECT_CATALOG_ROLE",
    "EXECUTE_CATALOG_ROLE",
    "LOGMINING",
    "CREATE TABLE",
    "LOCK ANY TABLE",
    "CREATE SEQUENCE",
)

# (object_name, privilege) pairs, granted via grant_sys_object. DBMS_LOGMNR /
# DBMS_LOGMNR_D need EXECUTE; every V_$ view needs SELECT.
CDC_SYS_OBJECT_GRANTS = (
    ("DBMS_LOGMNR", "EXECUTE"),
    ("DBMS_LOGMNR_D", "EXECUTE"),
    ("V_$DATABASE", "SELECT"),
    ("V_$LOG", "SELECT"),
    ("V_$LOG_HISTORY", "SELECT"),
    ("V_$LOGMNR_LOGS", "SELECT"),
    ("V_$LOGMNR_CONTENTS", "SELECT"),
    ("V_$LOGMNR_PARAMETERS", "SELECT"),
    ("V_$LOGFILE", "SELECT"),
    ("V_$ARCHIVED_LOG", "SELECT"),
    ("V_$ARCHIVE_DEST_STATUS", "SELECT"),
    ("V_$TRANSACTION", "SELECT"),
)

# An Oracle user identifier must be a bare, unquoted-form name. Oracle DDL
# cannot bind ANY variable (not even values — see module docstring), so this
# allowlist is the only defence against building an unsafe CREATE USER/GRANT
# statement. Applied BEFORE the name is ever composed into a statement.
CDC_USERNAME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_#$]{0,29}$")


class InputError(Exception):
    """A required input is missing or malformed.

    Carries a message safe to print to stderr — it names the offending input,
    never a credential value.
    """


class PreconditionError(Exception):
    """A LogMiner precondition is not satisfied on the source database.

    Raised by :func:`verify_preconditions` before any modification is made.
    Carries a message safe to print to stderr — it names the offending
    setting and, where applicable, the RDS control that governs it — and
    never a credential value.
    """


def _required(name: str) -> str:
    """Return the value of ``PROPELLER_INPUT_<name>`` or raise :class:`InputError`.

    The environment variable must be present and non-empty; a blank value is
    treated as missing so an accidentally-unset input fails loudly rather than
    silently becoming an empty host or parameter name.
    """
    value = os.environ.get(INPUT_PREFIX + name, "")
    if not value:
        raise InputError(f"missing required input: {INPUT_PREFIX}{name}")
    return value


def _required_int(name: str) -> int:
    """Return ``PROPELLER_INPUT_<name>`` parsed as an int, or raise."""
    raw = _required(name)
    try:
        return int(raw)
    except ValueError as exc:
        raise InputError(
            f"input {INPUT_PREFIX}{name} must be an integer, got: {raw!r}"
        ) from exc


def _optional_int(name: str, default: int) -> int:
    """Return ``PROPELLER_INPUT_<name>`` parsed as an int, or ``default``."""
    raw = os.environ.get(INPUT_PREFIX + name, "")
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise InputError(
            f"input {INPUT_PREFIX}{name} must be an integer, got: {raw!r}"
        ) from exc


def _optional(name: str, default: str) -> str:
    """Return ``PROPELLER_INPUT_<name>`` or ``default`` when unset/empty."""
    value = os.environ.get(INPUT_PREFIX + name, "")
    return value if value else default


@dataclass(frozen=True)
class Inputs:
    """Declared inputs, read from ``PROPELLER_INPUT_*`` environment variables."""

    db_host: str
    db_port: int
    service_name: str
    pdb_name: str
    admin_credential_parameter: str
    cdc_username: str
    cdc_username_parameter: str
    cdc_password_parameter: str
    archivelog_retention_hours: int
    kms_key_id: str


@dataclass(frozen=True)
class Clients:
    """The external clients this project talks to, constructed in one place.

    ``ssm`` — a boto3 SSM client.
    ``db``  — a python-oracledb thin-mode connection.

    Kept together so tests mock exactly at this boundary and no call site
    constructs a client of its own.
    """

    ssm: Any
    db: Any


def build_ssm_client() -> Any:
    """Construct the boto3 SSM client.

    Split out from :func:`build_clients` because :func:`main` needs the SSM
    client to read the administrative credential BEFORE the database
    connection can be opened (the credential is the DB login). boto3 is
    imported lazily so the input/credential readers stay unit-testable and
    ``py_compile`` succeeds even when boto3 is not installed.
    """
    import boto3  # lazy: not needed to unit-test the input/credential readers

    return boto3.client("ssm")


def build_clients(inputs: Inputs, admin_username: str, admin_password: str) -> Clients:
    """Construct the boto3 SSM client and the python-oracledb connection.

    This is the ONLY place ``oracledb`` is instantiated. python-oracledb runs
    in **thin mode by default** — no Oracle Instant Client, no OTN-licensed
    component — which is exactly why it was chosen for the deploy-runner image
    (Requirement 6.2). Thin mode is the default connection mode; no
    ``oracledb.init_oracle_client()`` call is made anywhere in this project, so
    thick mode is never activated.

    ``inputs.pdb_name`` selects which service the connection targets: on an
    Oracle multitenant (CDB) instance a client connects at the pluggable
    database (tenant database, in RDS terms) level, not the container level,
    so an empty ``pdb_name`` (non-CDB) connects via ``service_name`` directly
    while a non-empty one is used instead.

    oracledb is imported lazily inside this function so that
    :func:`read_inputs` and :func:`read_admin_credential` remain unit-testable
    with a mocked ``ssm`` object, and ``py_compile`` succeeds, even when the
    library is not installed in the verifying environment.

    On a connection or authentication failure, raises :class:`ConnectionError`
    with a message that names the host and port but never the credential;
    :func:`main` renders it to stderr with a non-zero exit.
    """
    import oracledb  # lazy: not needed to unit-test the input/credential readers

    ssm = build_ssm_client()

    service = inputs.pdb_name or inputs.service_name
    try:
        db = oracledb.connect(
            host=inputs.db_host,
            port=inputs.db_port,
            service_name=service,
            user=admin_username,
            password=admin_password,
        )
    except oracledb.Error as exc:
        # Report the endpoint and the driver's error class only — never the
        # credential value that failed.
        raise ConnectionError(
            f"could not connect to Oracle at {inputs.db_host}:{inputs.db_port}"
            f"/{service}: {type(exc).__name__}: {exc}"
        ) from exc

    return Clients(ssm=ssm, db=db)


def read_inputs() -> Inputs:
    """Read and validate the declared inputs from the environment.

    ``db_port`` defaults to :data:`DEFAULT_DB_PORT` (1521); ``kms_key_id``
    defaults to :data:`DEFAULT_KMS_KEY_ID`; ``archivelog_retention_hours``
    defaults to :data:`DEFAULT_ARCHIVELOG_RETENTION_HOURS`. ``pdb_name`` is
    optional and empty by default — a non-CDB RDS for Oracle instance has no
    pluggable database to name. A missing required input raises
    :class:`InputError`, which :func:`main` renders to stderr with a non-zero
    exit.

    Every parameter reference is a *name* supplied as an input — no path is
    hardcoded and no name is defaulted. The CDC credential is split across two
    named parameters (``cdc_username_parameter`` and ``cdc_password_parameter``)
    so the connector can read each with the SSM Config_Provider. A credential
    value is never read here; only the names of the parameters that hold or
    will hold them.
    """
    return Inputs(
        db_host=_required("db_host"),
        db_port=_optional_int("db_port", DEFAULT_DB_PORT),
        service_name=_required("service_name"),
        pdb_name=_optional("pdb_name", ""),
        admin_credential_parameter=_required("admin_credential_parameter"),
        cdc_username=_required("cdc_username"),
        cdc_username_parameter=_required("cdc_username_parameter"),
        cdc_password_parameter=_required("cdc_password_parameter"),
        archivelog_retention_hours=_optional_int(
            "archivelog_retention_hours", DEFAULT_ARCHIVELOG_RETENTION_HOURS
        ),
        kms_key_id=_optional("kms_key_id", DEFAULT_KMS_KEY_ID),
    )


def _parse_credential_value(value: str, fallback_username: str) -> tuple[str, str]:
    """Split a stored parameter value into ``(username, password)``.

    Identical contract to ``cdc-prepare-mariadb``'s function of the same name.
    Two stored forms are supported, because consumers differ:

    * **JSON document** — the value is ``{"username": ..., "password": ...}``.
      Both fields are taken from the document.
    * **Scalar password** — the value is the password itself (any value that is
      not a JSON object carrying both keys). The username is then taken from
      ``fallback_username``.

    A value that parses as JSON but is not an object with both ``username`` and
    ``password`` keys is treated as the scalar-password form.
    """
    try:
        parsed = json.loads(value)
    except (ValueError, TypeError):
        parsed = None

    if isinstance(parsed, dict) and "username" in parsed and "password" in parsed:
        return str(parsed["username"]), str(parsed["password"])

    return fallback_username, value


def read_admin_credential(
    ssm: Any, parameter_name: str, fallback_username: str
) -> tuple[str, str]:
    """Read the administrative credential from the parameter *named* by input.

    Identical contract to ``cdc-prepare-mariadb``'s function of the same name:
    fetches ``parameter_name`` from SSM with ``WithDecryption=True`` and
    returns ``(username, password)`` via :func:`_parse_credential_value`.

    The credential value is never logged, returned in an error message, or
    otherwise emitted.
    """
    response = ssm.get_parameter(Name=parameter_name, WithDecryption=True)
    return _parse_credential_value(response["Parameter"]["Value"], fallback_username)


def _resolve_scalar_parameter(
    ssm: Any, parameter_name: str, value_if_absent: Callable[[], str], kms_key_id: str
) -> str:
    """Resolve one scalar ``SecureString`` parameter, creating it if absent.

    Identical contract to ``cdc-prepare-mariadb``'s function of the same name.
    The parameter is the SOURCE OF TRUTH for the single value it holds:

    * If it already exists, its stored scalar value is read with decryption and
      returned UNCHANGED — this function never writes to an existing parameter.
      There is no rotation.
    * If it does not exist, it is CREATED as a scalar ``SecureString`` holding
      the value ``value_if_absent()`` produces, encrypted with ``kms_key_id``,
      and that value is returned.

    ``value_if_absent`` is a callable, not a plain value, so the password is
    generated ONLY when the password parameter is actually absent — a re-run
    against an existing parameter must generate nothing.

    The value is stored and read verbatim, not wrapped in a JSON document,
    because the connector's SSM Config_Provider resolves ``$${ssm::<name>}`` to
    the parameter's entire value and cannot extract a key out of JSON (see
    module docstring).

    A credential value is never logged, returned in an error message, or
    otherwise emitted.
    """
    try:
        response = ssm.get_parameter(Name=parameter_name, WithDecryption=True)
    except ssm.exceptions.ParameterNotFound:
        value = value_if_absent()
        ssm.put_parameter(
            Name=parameter_name,
            Value=value,
            Type="SecureString",
            KeyId=kms_key_id,
        )
        return value

    return str(response["Parameter"]["Value"])


def resolve_cdc_credential(
    ssm: Any,
    username_parameter: str,
    password_parameter: str,
    fallback_username: str,
    kms_key_id: str,
) -> tuple[str, str]:
    """Resolve the CDC_User credential from TWO named scalar SSM parameters.

    Identical contract to ``cdc-prepare-mariadb``'s function of the same name.
    Each parameter is resolved independently by :func:`_resolve_scalar_parameter`
    and is the SOURCE OF TRUTH for the value it holds:

    * ``username_parameter`` — read unchanged if it exists; created holding
      ``fallback_username`` (the ``cdc_username`` input) if it does not.
    * ``password_parameter`` — read unchanged if it exists; created holding a
      freshly generated password (:func:`secrets.token_urlsafe`) if it does
      not.

    The password is generated only when the password parameter is absent, so a
    username-only or password-only pre-existing state is handled correctly.
    Neither parameter is ever overwritten — there is no rotation.

    The credential value is never logged, returned in an error message, or
    otherwise emitted.
    """
    username = _resolve_scalar_parameter(
        ssm, username_parameter, lambda: fallback_username, kms_key_id
    )
    password = _resolve_scalar_parameter(
        ssm, password_parameter, lambda: secrets.token_urlsafe(32), kms_key_id
    )
    return username, password


def _query_one(db: Any, sql: str) -> tuple[Any, ...] | None:
    """Run a fixed, literal-only read query and return its single row, or None.

    ``sql`` must be a fixed literal internal to this module, never
    input-derived — this function only READS system views and issues no
    statement that could modify server state. The cursor is always closed.
    """
    cursor = db.cursor()
    try:
        cursor.execute(sql)
        return cursor.fetchone()
    finally:
        cursor.close()


def verify_preconditions(db: Any) -> None:
    """Verify LogMiner preconditions BEFORE any modification.

    Checks, in order, that:

    * the database is in ``ARCHIVELOG`` mode (``V$DATABASE.LOG_MODE``) — else
      name the RDS control that governs it: RDS for Oracle generates archived
      redo logs only when the automated-backup retention period is non-zero;
    * database-level supplemental logging is at least minimal
      (``V$DATABASE.SUPPLEMENTAL_LOG_DATA_MIN``) — LogMiner cannot reconstruct
      row changes without it;
    * primary-key supplemental logging is enabled
      (``V$DATABASE.SUPPLEMENTAL_LOG_DATA_PK``) — without it, an UPDATE/DELETE
      redo record may not carry enough of the old row to identify which row
      changed.

    All three are read from a single ``SELECT ... FROM V_$DATABASE`` (the
    RDS-grantable ``V_$`` alias for ``V$DATABASE``) against a read-only cursor
    on ``db`` — the mockable client boundary. The query is a fixed literal, so
    no input flows into any statement and this function performs no
    modification — there is nothing to undo because it runs first.

    On any failure, raises :class:`PreconditionError` with a message that
    names the offending setting and its required value; :func:`main` renders
    it to stderr with a non-zero exit.
    """
    row = _query_one(
        db,
        "SELECT LOG_MODE, SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK "
        "FROM V_$DATABASE",
    )
    if row is None:
        raise PreconditionError(
            "could not read V_$DATABASE; the admin credential may lack "
            "SELECT on V_$DATABASE"
        )
    log_mode, supp_min, supp_pk = row

    # 1. ARCHIVELOG mode. On RDS for Oracle, archive logging is a side effect
    #    of a non-zero automated-backup retention period, so a failure here
    #    points the operator at that control rather than at a setting they
    #    cannot change directly with SQL.
    if (str(log_mode) or "").upper() != "ARCHIVELOG":
        raise PreconditionError(
            f"database is not in ARCHIVELOG mode: LOG_MODE is {log_mode!r}, "
            "expected 'ARCHIVELOG'. On RDS for Oracle, archive logging is a "
            "side effect of setting the instance's automated-backup "
            "retention period (backup_retention_period) to a non-zero "
            "value; RDS for Oracle generates NO archived redo logs at all "
            "with zero backup retention."
        )

    # 2. Minimal supplemental logging must be enabled at the database level.
    if (str(supp_min) or "").upper() not in ("YES", "IMPLICIT"):
        raise PreconditionError(
            "database-level supplemental logging is not enabled: "
            f"SUPPLEMENTAL_LOG_DATA_MIN is {supp_min!r}, expected 'YES'. "
            "Enable it via "
            "rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD')."
        )

    # 3. Primary-key supplemental logging must be enabled.
    if (str(supp_pk) or "").upper() != "YES":
        raise PreconditionError(
            "primary-key supplemental logging is not enabled: "
            f"SUPPLEMENTAL_LOG_DATA_PK is {supp_pk!r}, expected 'YES'. "
            "Enable it via rdsadmin.rdsadmin_util.alter_supplemental_logging"
            "('ADD', 'PRIMARY KEY')."
        )


def _validated_identifier(name: str, *, what: str) -> str:
    """Return ``name`` if it is a safe bare Oracle identifier, else raise.

    Oracle DDL cannot bind ANY variable, so every identifier this module
    composes into a statement — the CDC username above all — is validated
    against this allowlist first. Anything outside
    ``[A-Za-z][A-Za-z0-9_#$]{0,29}`` (Oracle's own unquoted-identifier grammar,
    30-byte name limit) is rejected with a clear :class:`InputError` naming
    which value failed, never the value itself if it might be a credential
    (it never is here — this function is only used for identifiers).
    """
    if not CDC_USERNAME_PATTERN.match(name):
        raise InputError(
            f"{what} must be a valid bare Oracle identifier matching "
            f"{CDC_USERNAME_PATTERN.pattern!r}; refusing to compose it into "
            "a DDL statement"
        )
    return name


def _quoted_literal(value: str) -> str:
    """Return ``value`` as a single-quoted Oracle SQL literal, safely escaped.

    Oracle DDL (``CREATE USER ... IDENTIFIED BY``, and the ``rdsadmin_util``
    calls below, which are PL/SQL blocks rather than bindable OCI calls in the
    way this project issues them) cannot take a bind variable, so the
    password — a genuine *value*, not an identifier — is escaped and quoted
    here rather than allowlisted. Oracle's escaping rule for a single-quoted
    literal is to double every embedded single quote; there is no other
    special character to handle inside a quoted literal.

    This is the one place a credential value is composed into SQL text in
    this module. The composed statement is never logged (see ``run_ddl``).
    """
    return "'" + value.replace("'", "''") + "'"


def run_ddl(db: Any, statement: str) -> None:
    """Run one DDL/PL-SQL statement that composes its own literals, then commit.

    Oracle does not support bind variables in DDL statements (or in
    `EXEC`-style anonymous PL/SQL blocks the way this project uses them), so
    every value this module needs to compose into ``statement`` MUST already
    have passed through :func:`_validated_identifier` (an identifier) or
    :func:`_quoted_literal` (a value) before reaching this function — never
    raw. ``statement`` itself is never printed in an error path that could
    surface a composed credential; callers report a fixed, generic message on
    failure instead.

    A cursor is opened, the statement executed, the cursor closed, and the
    connection committed — Oracle DDL auto-commits implicitly, but the
    ``rdsadmin_util`` PL/SQL calls this module also runs through here do not,
    so an explicit commit is always issued to keep both paths uniform and
    correct (the AWS documentation for `set_configuration` states the commit
    is required).
    """
    cursor = db.cursor()
    try:
        cursor.execute(statement)
    finally:
        cursor.close()
    db.commit()


def create_cdc_user(clients: Clients, inputs: Inputs) -> None:
    """Resolve the CDC credential, create/grant the CDC_User, and set retention.

    Ordered flow, every step idempotent:

    a. Resolve the credential from the two named SSM parameters via
       :func:`resolve_cdc_credential` — each parameter is the SOURCE OF TRUTH
       for its value: an existing username/password parameter is read
       unchanged, a missing one is created. There is no rotation: an existing
       parameter is never overwritten.
    b. Determine whether the database account already exists
       (``SELECT COUNT(*) FROM ALL_USERS WHERE USERNAME = ...`` — composed as
       an uppercase literal because Oracle stores unquoted identifiers
       uppercased and ``ALL_USERS`` cannot be queried with a bind variable in
       an anonymous-block-free ``SELECT`` here any more safely than the DDL
       below; the value is still a *comparison literal*, safely quoted).
    c. ``CREATE USER <validated> IDENTIFIED BY <quoted>`` using the password
       resolved in (a), ONLY when the account does not yet exist — Oracle has
       no ``IF NOT EXISTS`` form of ``CREATE USER``, so this statement is only
       issued when step (b) found the account absent. When the account
       already exists, this step is skipped entirely: the database password
       is never reset from here, matching the parameter's own no-rotation
       guarantee.
    d. ``GRANT`` each of :data:`CDC_SYSTEM_GRANTS` — naturally idempotent
       (re-granting an already-held privilege is a no-op, not an error).
    e. Transfer each of :data:`CDC_SYS_OBJECT_GRANTS` via
       ``rdsadmin.rdsadmin_util.grant_sys_object`` — also idempotent per the
       AWS documentation ("if you use the grant_sys_object procedure to
       re-grant access, the procedure call succeeds").
    f. On first creation of the DATABASE ACCOUNT only, set the archive-log
       retention window via ``rdsadmin.rdsadmin_util.set_configuration
       ('archivelog retention hours', ...)`` followed by the commit AWS's
       documentation states is required. This mirrors cdc-prepare-mariadb's
       binlog-retention step, except it is deliberately gated to
       first-creation: a re-run must not silently change a retention window
       an operator may have since tuned (unlike the grants, which converge to
       the same fixed target every time).

    A credential VALUE is never printed, logged, or placed in an error
    message.
    """
    db = clients.db
    ssm = clients.ssm

    # (a) Resolve the credential: read each existing parameter unchanged, or
    #     create the missing one (username from the input, password generated).
    username, password = resolve_cdc_credential(
        ssm,
        inputs.cdc_username_parameter,
        inputs.cdc_password_parameter,
        inputs.cdc_username,
        inputs.kms_key_id,
    )
    # Validate the resolved username before it is used to build any statement
    # (grammar-forced identifier composition — see run_ddl). The parameter may
    # be an existing one supplied by the consumer, so this still applies even
    # when the username did not come from inputs.cdc_username.
    username = _validated_identifier(username, what="cdc_username")
    username_upper = username.upper()  # Oracle stores unquoted names uppercased.

    # (b) Does the account already exist?
    row = _query_one(
        db,
        f"SELECT COUNT(*) FROM ALL_USERS WHERE USERNAME = {_quoted_literal(username_upper)}",
    )
    user_exists = bool(row and row[0])

    # (c) Create the account only when absent, using the resolved password.
    #     Oracle CREATE USER has no IF NOT EXISTS, so this branch is skipped
    #     entirely on a re-run rather than issuing a statement that would fail
    #     (or, worse, that some Oracle version might interpret as resetting
    #     the password).
    if not user_exists:
        run_ddl(
            db,
            f"CREATE USER {username} IDENTIFIED BY {_quoted_literal(password)}",
        )

    # (d) Grant the ordinary system privileges/roles. Idempotent: re-granting
    #     an already-held privilege succeeds as a no-op.
    for grant in CDC_SYSTEM_GRANTS:
        run_ddl(db, f"GRANT {grant} TO {username}")

    # (e) Transfer the SYS-owned package/view privileges via grant_sys_object
    #     — the RDS-specific mechanism, because the master user is not real
    #     SYS and a plain GRANT on these objects fails with ORA-01031.
    for obj_name, privilege in CDC_SYS_OBJECT_GRANTS:
        run_ddl(
            db,
            "BEGIN rdsadmin.rdsadmin_util.grant_sys_object("
            f"p_obj_name => {_quoted_literal(obj_name)}, "
            f"p_grantee => {_quoted_literal(username_upper)}, "
            f"p_privilege => {_quoted_literal(privilege)}); END;",
        )

    # (f) Set the archive-log retention window, but ONLY on first creation of
    #     the database account — a re-run must not silently override a value
    #     an operator has since tuned. The AWS documentation for this
    #     procedure states a commit is required for the change to take
    #     effect; run_ddl always commits.
    if not user_exists:
        run_ddl(
            db,
            "BEGIN rdsadmin.rdsadmin_util.set_configuration("
            "name => 'archivelog retention hours', "
            f"value => {_quoted_literal(str(inputs.archivelog_retention_hours))}); END;",
        )


def main() -> int:
    """Ordered preparation flow. Returns a process exit code."""
    try:
        # Read and validate declared inputs. A missing or malformed required
        # input aborts here with a descriptive message and exit 2, before any
        # client is constructed or any modification attempted.
        inputs = read_inputs()

        # Construct the SSM client first so the admin credential can be read
        # before the database connection is opened (the credential IS the DB
        # login). build_ssm_client and build_clients between them confine all
        # client construction, keeping every other function mockable.
        ssm = build_ssm_client()
        admin_username, admin_password = read_admin_credential(
            ssm, inputs.admin_credential_parameter, inputs.cdc_username
        )
        clients = build_clients(inputs, admin_username, admin_password)

        # Verify every precondition BEFORE any modification.
        verify_preconditions(clients.db)

        # Create the CDC user, grant it, resolve its credential, set
        # retention on first creation. Idempotent and safe to re-run.
        create_cdc_user(clients, inputs)

        # Non-secret success summary: the user name and the parameter name
        # holding its credential — never a credential value.
        print(
            "cdc-prepare-oracle: prepared CDC user "
            f"{inputs.cdc_username!r}; credential resolved from parameters "
            f"{inputs.cdc_username_parameter!r} (username) and "
            f"{inputs.cdc_password_parameter!r} (password)"
        )
        return 0
    except InputError as exc:
        print(f"cdc-prepare-oracle: {exc}", file=sys.stderr)
        return 2
    except PreconditionError as exc:
        print(f"cdc-prepare-oracle: precondition failed: {exc}", file=sys.stderr)
        return 1
    except ConnectionError as exc:
        print(f"cdc-prepare-oracle: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
