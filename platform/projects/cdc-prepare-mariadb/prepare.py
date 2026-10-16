#!/usr/bin/env python3
"""Prepare a MariaDB source database for Debezium CDC.

Idempotent, re-runnable preparation of one MariaDB instance:

1. Read inputs from the environment (``PROPELLER_INPUT_*``).
2. Read the administrative credential from the SSM parameter *named* by an
   input (never a hardcoded path).
3. Verify binary-logging preconditions BEFORE making any modification.
4. Create a least-privilege ``CDC_User`` with exactly five grants, set the
   binary-log retention window, and resolve the user's credential from TWO
   separate, named SSM ``SecureString`` parameters — one holding the username,
   one holding the password. Each is resolved independently: if a parameter
   already exists, it is the SOURCE OF TRUTH and is never overwritten by this
   project; if it does not exist, it is created (the username parameter from
   the ``cdc_username`` input, the password parameter from a freshly generated
   password), each as a scalar ``SecureString`` encrypted with the supplied KMS
   key. There is no rotation: to change a credential, change the parameter
   directly, or manage it from a separate project — this project only fills a
   parameter in when it is absent.

   Two SCALAR parameters (not one JSON document) are used deliberately: the
   downstream ``msk-connect-debezium`` connector reads each with the SSM
   Config_Provider (``$${ssm::<name>}``), which resolves a placeholder to the
   parameter's whole value and cannot extract a key out of a JSON document.
   A scalar-per-value shape is therefore the only one the connector's
   ``database.user`` / ``database.password`` read path accepts. See the module
   README and the project README's "Credential handling" section.

Nothing about the host, user, parameter names, account or region is hardcoded;
every environment-specific value arrives as a ``PROPELLER_INPUT_*`` variable
(Requirement 7). This project requires no AWS access to *build* or test — it is
exercised entirely through mocked clients (see the project tests) — but at run
time it must execute on an In_VPC_Runner able to reach the database and
Parameter Store.

A credential VALUE is never written to stdout, stderr, or any output.

Implementation note: the AWS (boto3 SSM) and database (PyMySQL) clients are
constructed in exactly one place — :func:`build_clients` — so that tests can
mock at the client boundary (design.md, Testing Strategy). The rest of the
module receives already-constructed clients and never imports boto3 or PyMySQL
at call sites.

Implemented across tasks 1.11 (inputs, admin credential, client boundary),
1.12 (preconditions) and 1.13 (CDC user creation, credential publication, and
the full apply wiring in :func:`main`).
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
# kms_key_id input is supplied: the AWS-managed SSM key (Requirement 3.17).
DEFAULT_KMS_KEY_ID = "alias/aws/ssm"

# Note on the credential shape: the CDC username and password are stored in TWO
# separate scalar SecureString parameters, not one JSON document. The connector
# reads each via the SSM Config_Provider, which cannot extract a key out of JSON
# (see module docstring). read_admin_credential below still accepts a JSON
# document OR a scalar because the ADMIN credential is read, not written by this
# project, and consumers store it either way — that is a different contract from
# the two scalar parameters this project creates for the CDC user.

# Every environment-specific value arrives as a PROPELLER_INPUT_* variable. The
# prefix is defined once here so the reader never spells it inline (Requirement 7).
INPUT_PREFIX = "PROPELLER_INPUT_"

# Default MariaDB port used when the db_port input is not supplied.
DEFAULT_DB_PORT = 3306

# The exact five grants the CDC_User needs — no more (Requirement 3.5). Kept as
# a module constant so the grant statement is built from a single source of
# truth and a test can assert the set has not drifted.
CDC_GRANTS = (
    "SELECT",
    "RELOAD",
    "SHOW DATABASES",
    "REPLICATION SLAVE",
    "REPLICATION CLIENT",
)

# A CDC username must be a bare identifier. MySQL/MariaDB does not allow a
# parameter placeholder for the username in CREATE USER / GRANT (it is an
# identifier-like literal, not a bindable value), so the only safe defence is a
# strict allowlist applied BEFORE the name is ever placed into a statement. Any
# character outside this set is rejected (see run_sql / _validated_username).
CDC_USERNAME_PATTERN = re.compile(r"^[A-Za-z0-9_]+$")


class InputError(Exception):
    """A required input is missing or malformed.

    Carries a message safe to print to stderr — it names the offending input,
    never a credential value.
    """


class PreconditionError(Exception):
    """A binary-logging precondition is not satisfied on the source database.

    Raised by :func:`verify_preconditions` before any modification is made.
    Carries a message safe to print to stderr — it names the offending server
    setting and, where applicable, the RDS control that governs it — and never
    a credential value.
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
    """Return ``PROPELLER_INPUT_<name>`` parsed as an int, or raise.

    Rejects a missing or non-integer value with a descriptive error naming the
    input variable.
    """
    raw = _required(name)
    try:
        return int(raw)
    except ValueError as exc:
        raise InputError(
            f"input {INPUT_PREFIX}{name} must be an integer, got: {raw!r}"
        ) from exc


def _optional_int(name: str, default: int) -> int:
    """Return ``PROPELLER_INPUT_<name>`` parsed as an int, or ``default``.

    An unset or empty variable yields ``default``; a present-but-non-integer
    value is an error naming the input variable.
    """
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
    """Declared inputs, read from ``PROPELLER_INPUT_*`` environment variables.

    Populated by :func:`read_inputs` (task 1.11). Field set is fixed here so the
    later task fills the reader, not the shape.
    """

    db_host: str
    db_port: int
    admin_credential_parameter: str
    cdc_username: str
    cdc_username_parameter: str
    cdc_password_parameter: str
    binlog_retention_hours: int
    kms_key_id: str


@dataclass(frozen=True)
class Clients:
    """The external clients this project talks to, constructed in one place.

    ``ssm``  — a boto3 SSM client.
    ``db``   — a PyMySQL connection.

    Kept together so tests mock exactly at this boundary and no call site
    constructs a client of its own.
    """

    ssm: Any
    db: Any


def build_ssm_client() -> Any:
    """Construct the boto3 SSM client.

    Split out from :func:`build_clients` because :func:`main` needs the SSM
    client to read the administrative credential BEFORE the database connection
    can be opened (the credential is the DB login). Keeping the ``boto3.client``
    call here — used by both :func:`build_clients` and :func:`main` — preserves
    the single-client-boundary principle: no other call site instantiates a
    boto3 client, so tests mock exactly here.

    boto3 is imported lazily so the input/credential readers stay unit-testable
    and ``py_compile`` succeeds even when boto3 is not installed.
    """
    import boto3  # lazy: not needed to unit-test the input/credential readers

    return boto3.client("ssm")


def build_clients(inputs: Inputs, admin_username: str, admin_password: str) -> Clients:
    """Construct the boto3 SSM client and the PyMySQL connection.

    This is the ONLY place PyMySQL is instantiated and, together with
    :func:`build_ssm_client`, confines all external-client construction so the
    tests can substitute mocks here and exercise every other function with plain
    objects.

    PyMySQL is imported lazily inside this function so that :func:`read_inputs`
    and :func:`read_admin_credential` remain unit-testable with a mocked ``ssm``
    object, and ``py_compile`` succeeds, even when the library is not installed
    in the verifying environment.

    On a connection or authentication failure, raises
    :class:`ConnectionError` with a message that names the host and port but
    never the credential; :func:`main` renders it to stderr with a non-zero exit
    (Requirement 3.16).
    """
    import pymysql  # lazy: not needed to unit-test the input/credential readers

    ssm = build_ssm_client()

    try:
        db = pymysql.connect(
            host=inputs.db_host,
            port=inputs.db_port,
            user=admin_username,
            password=admin_password,
        )
    except pymysql.MySQLError as exc:
        # Report the endpoint and the driver's error class only — never the
        # credential value that failed (Requirements 3.13, 3.16).
        raise ConnectionError(
            f"could not connect to MariaDB at {inputs.db_host}:{inputs.db_port}: "
            f"{type(exc).__name__}: {exc}"
        ) from exc

    return Clients(ssm=ssm, db=db)


def read_inputs() -> Inputs:
    """Read and validate the declared inputs from the environment.

    Reads each ``PROPELLER_INPUT_*`` variable into an :class:`Inputs`.
    ``db_port`` defaults to :data:`DEFAULT_DB_PORT` (3306); ``kms_key_id``
    defaults to :data:`DEFAULT_KMS_KEY_ID`. A missing required input raises
    :class:`InputError`, which :func:`main` renders to stderr with a non-zero
    exit.

    Every parameter reference is a *name* supplied as an input — no path is
    hardcoded and no name is defaulted (Requirements 3.2, 3.3, 3.4, 3.17, 7.1,
    7.2, 7.3). The CDC credential is split across two named parameters
    (``cdc_username_parameter`` and ``cdc_password_parameter``) so the connector
    can read each with the SSM Config_Provider. A credential value is never read
    here; only the names of the parameters that hold or will hold them.
    """
    return Inputs(
        db_host=_required("db_host"),
        db_port=_optional_int("db_port", DEFAULT_DB_PORT),
        admin_credential_parameter=_required("admin_credential_parameter"),
        cdc_username=_required("cdc_username"),
        cdc_username_parameter=_required("cdc_username_parameter"),
        cdc_password_parameter=_required("cdc_password_parameter"),
        binlog_retention_hours=_required_int("binlog_retention_hours"),
        kms_key_id=_optional("kms_key_id", DEFAULT_KMS_KEY_ID),
    )


def _parse_credential_value(value: str, fallback_username: str) -> tuple[str, str]:
    """Split a stored parameter value into ``(username, password)``.

    Two stored forms are supported, because consumers differ (design.md,
    ``cdc-prepare-mariadb`` step 1):

    * **JSON document** — the value is ``{"username": ..., "password": ...}``.
      Both fields are taken from the document.
    * **Scalar password** — the value is the password itself (any value that is
      not a JSON object carrying both keys). The username is then taken from
      ``fallback_username``, matching the convention where the username is
      fixed by convention and only the password is stored.

    A value that parses as JSON but is not an object with both ``username`` and
    ``password`` keys (e.g. a bare JSON string, number, or a dict missing a
    key) is treated as the scalar-password form.
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

    Fetches ``parameter_name`` from SSM with ``WithDecryption=True`` and returns
    ``(username, password)`` via :func:`_parse_credential_value` (JSON-document
    or scalar-password form — see that function).

    The credential value is never logged, returned in an error message, or
    otherwise emitted.
    """
    response = ssm.get_parameter(Name=parameter_name, WithDecryption=True)
    return _parse_credential_value(response["Parameter"]["Value"], fallback_username)


def _resolve_scalar_parameter(
    ssm: Any, parameter_name: str, value_if_absent: Callable[[], str], kms_key_id: str
) -> str:
    """Resolve one scalar ``SecureString`` parameter, creating it if absent.

    The parameter is the SOURCE OF TRUTH for the single value it holds:

    * If it already exists, its stored scalar value is read with decryption and
      returned UNCHANGED — this function never writes to an existing parameter.
      There is no rotation: to change the value, edit the parameter directly,
      or manage it from a separate project.
    * If it does not exist, it is CREATED as a scalar ``SecureString`` holding
      the value ``value_if_absent()`` produces (the ``cdc_username`` input for
      the username parameter, or a freshly generated password for the password
      parameter), encrypted with ``kms_key_id``, and that value is returned.

    ``value_if_absent`` is a callable, not a plain value, so the password is
    generated ONLY when the password parameter is actually absent — a re-run
    against an existing parameter must generate nothing (Requirement 3.8).

    The value is stored and read as the parameter's whole verbatim content, not
    wrapped in a JSON document, because the connector's SSM Config_Provider
    resolves ``$${ssm::<name>}`` to the parameter's entire value and cannot
    extract a key out of JSON (see module docstring).

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

    Each parameter is resolved independently by :func:`_resolve_scalar_parameter`
    and is the SOURCE OF TRUTH for the value it holds:

    * ``username_parameter`` — read unchanged if it exists; created holding
      ``fallback_username`` (the ``cdc_username`` input) if it does not.
    * ``password_parameter`` — read unchanged if it exists; created holding a
      freshly generated password (:func:`secrets.token_urlsafe`) if it does
      not.

    The password is generated only when the password parameter is absent, so a
    username-parameter-only or password-parameter-only pre-existing state is
    handled correctly: whichever parameter already exists is read, and only the
    missing one is created. Neither is ever overwritten — there is no rotation.

    ``fallback_username`` is used ONLY to create the username parameter when it
    is absent. Once that parameter exists, the username it stores is
    authoritative, even if it differs from a later ``cdc_username`` input value.

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


def _read_variable(db: Any, name: str) -> str | None:
    """Return the value of a MariaDB server variable, or ``None`` if absent.

    Runs ``SHOW VARIABLES LIKE '<name>'`` on a cursor from ``db`` and returns
    the value column of the single matching row. Returns ``None`` when the
    server does not expose the variable at all (an empty result set), so that a
    caller can distinguish "not present" from a concrete value.

    The variable names passed here are fixed literals internal to this module,
    never input-derived, so there is no SQL-injection surface. This function
    only READS — it issues no statement that could modify server state.

    The cursor is always closed, whether or not a row is returned.
    """
    cursor = db.cursor()
    try:
        cursor.execute("SHOW VARIABLES LIKE %s", (name,))
        row = cursor.fetchone()
    finally:
        cursor.close()

    if not row:
        return None
    # SHOW VARIABLES yields (Variable_name, Value); the value is the second
    # column regardless of whether the driver returns a tuple or a mapping.
    if isinstance(row, dict):
        return str(row.get("Value"))
    return str(row[1])


def verify_preconditions(db: Any) -> None:
    """Verify binary-logging preconditions BEFORE any modification.

    Checks, in order, that:
      * ``log_bin`` is active — else name the automated-backup retention
        setting that controls it (Requirement 3.10);
      * ``binlog_format`` is ``ROW`` (Requirement 3.11);
      * ``binlog_row_image`` is ``FULL`` (Requirement 3.11);
      * ``log_bin_compress`` is OFF — Debezium cannot read a compressed binary
        log (Requirement 3.12).

    Each value is read with ``SHOW VARIABLES LIKE`` against a read-only cursor
    on ``db`` (the mockable client boundary). All variable names are fixed
    literals, so no input flows into any statement and this function performs
    no modification — there is nothing to undo because it runs first
    (Requirement 3.9).

    On any failure, raises :class:`PreconditionError` with a message that names
    the offending setting and its required value; :func:`main` renders it to
    stderr with a non-zero exit.
    """
    # 1. Binary logging must be active. On RDS MariaDB, binary logging is turned
    #    on by giving the instance a non-zero automated-backup retention period,
    #    so a failure here points the operator at that control rather than at a
    #    server variable they cannot set directly (Requirement 3.10).
    log_bin = _read_variable(db, "log_bin")
    if (log_bin or "").upper() != "ON":
        raise PreconditionError(
            "binary logging is not active: log_bin is "
            f"{log_bin!r}, expected 'ON'. On RDS MariaDB, binary logging is "
            "enabled by setting the instance's automated-backup retention "
            "period (backup_retention_period) to a non-zero value."
        )

    # 2. binlog_format must be ROW (Requirement 3.11).
    binlog_format = _read_variable(db, "binlog_format")
    if (binlog_format or "").upper() != "ROW":
        raise PreconditionError(
            f"binlog_format is {binlog_format!r}, expected 'ROW'. Debezium "
            "requires row-based binary logging."
        )

    # 3. binlog_row_image must be FULL (Requirement 3.11).
    binlog_row_image = _read_variable(db, "binlog_row_image")
    if (binlog_row_image or "").upper() != "FULL":
        raise PreconditionError(
            f"binlog_row_image is {binlog_row_image!r}, expected 'FULL'. "
            "Debezium requires the full before/after row image."
        )

    # 4. log_bin_compress must be OFF (Requirement 3.12). This is a MariaDB
    #    variable that does not exist on every version; when the server does
    #    not expose it at all, the binary log cannot be compressed, so its
    #    absence is treated as not-enabled. Only a present-and-ON value fails.
    log_bin_compress = _read_variable(db, "log_bin_compress")
    if log_bin_compress is not None and log_bin_compress.upper() == "ON":
        raise PreconditionError(
            "log_bin_compress is 'ON'; Debezium cannot read a compressed "
            "binary log. Set log_bin_compress to OFF."
        )


def _validated_username(username: str) -> str:
    """Return ``username`` if it is a safe bare identifier, else raise.

    MySQL/MariaDB does NOT accept a parameter placeholder for the account name
    in ``CREATE USER`` or ``GRANT`` — the name is an identifier-like literal, not
    a bindable value the way a password in ``IDENTIFIED BY %s`` is. Because the
    name therefore has to be composed into the statement text, the only safe
    defence against injection is a strict allowlist applied here, before the name
    is placed anywhere near a statement. Anything outside ``[A-Za-z0-9_]`` is
    rejected with a clear :class:`InputError`.

    This is the deliberate, documented exception to "always parameterise": the
    username is allowlist-validated instead of bound; every genuine *value*
    (notably the password) is still bound by the driver — see
    :func:`create_cdc_user`.
    """
    if not CDC_USERNAME_PATTERN.match(username):
        raise InputError(
            "cdc_username must contain only letters, digits and underscores "
            f"(matched against {CDC_USERNAME_PATTERN.pattern!r}); refusing to "
            "build a CREATE USER/GRANT statement with an unsafe identifier"
        )
    return username


def run_sql(db: Any, statement: str, params: tuple[Any, ...] = ()) -> Any:
    """Run a single parameterised SQL statement and return its fetched rows.

    Every value derived from an input MUST be passed through ``params`` and bound
    by the driver, never interpolated into ``statement`` (Requirement 3.14). The
    one grammar-forced exception is an account *identifier* (a username in
    ``CREATE USER``/``GRANT``), which MariaDB will not accept as a placeholder;
    such identifiers are allowlist-validated by :func:`_validated_username`
    before they reach this function, never passed here as free text.

    A cursor is opened on ``db``, ``execute(statement, params)`` binds the
    params, any result rows are fetched and returned, and the cursor is always
    closed. When the connection is not autocommitting, ``db.commit()`` is called
    so a modifying statement is durable; a driver that autocommits exposes
    ``db.get_autocommit()`` returning ``True`` and is left alone.
    """
    cursor = db.cursor()
    try:
        cursor.execute(statement, params)
        # Not every statement returns rows (DDL/GRANT/CALL); fetchall on such a
        # cursor is harmless and yields an empty result for callers that ignore
        # it, while SELECTs return their rows.
        try:
            rows = cursor.fetchall()
        except Exception:
            rows = ()
    finally:
        cursor.close()

    # Commit unless the connection autocommits. PyMySQL connections default to
    # autocommit off, so a modifying statement must be committed to persist.
    autocommit = False
    getter = getattr(db, "get_autocommit", None)
    if callable(getter):
        autocommit = bool(getter())
    if not autocommit:
        db.commit()

    return rows


def create_cdc_user(clients: Clients, inputs: Inputs) -> None:
    """Resolve the CDC credential, create/grant the CDC_User, and set retention.

    Ordered flow, every step idempotent:

    a. Resolve the credential from the two named SSM parameters via
       :func:`resolve_cdc_credential` — each parameter is the SOURCE OF TRUTH
       for its value: an existing username/password parameter is read
       UNCHANGED; a missing one is created (the username from ``cdc_username``,
       the password freshly generated). There is no rotation: an existing
       parameter is never overwritten by this project (see that function).
    b. Determine whether the database account already exists
       (``SELECT 1 FROM mysql.user WHERE User=%s AND Host=%s`` — the username
       is a *value* in this predicate and IS bound as ``%s``).
    c. ``CREATE USER IF NOT EXISTS '<validated>'@'%' IDENTIFIED BY %s`` ONLY
       when the account does not yet exist, using the password resolved in
       (a) — the password is bound as a value; the username is
       allowlist-validated and composed into the statement text because
       MariaDB will not bind it. When the account already exists, this step
       is skipped entirely: the database password is never reset from here,
       matching the parameter's own no-rotation guarantee.
    d. ``GRANT`` exactly the five :data:`CDC_GRANTS` on ``*.*`` — naturally
       idempotent (Requirement 3.5).
    e. ``CALL mysql.rds_set_configuration('binlog retention hours', %s)`` with
       ``inputs.binlog_retention_hours`` bound (Requirement 3.7).

    A credential VALUE is never printed, logged, or placed in an error message
    (Requirement 3.13).
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
    # (grammar-forced identifier composition — see run_sql). The parameter may
    # be an existing one supplied by the consumer, so this still applies even
    # when the username did not come from inputs.cdc_username.
    username = _validated_username(username)

    # (b) Does the account already exist? The username here is a bound *value*
    #     in a WHERE predicate — safe and correct to parameterise.
    existing = run_sql(
        db,
        "SELECT 1 FROM mysql.user WHERE User = %s AND Host = %s",
        (username, "%"),
    )
    user_exists = bool(existing)

    # (c) Create the account only when absent, using the resolved password.
    #     IF NOT EXISTS keeps this idempotent; the password is bound. When the
    #     account already exists this is skipped — its password is never reset
    #     from here.
    if not user_exists:
        run_sql(
            db,
            f"CREATE USER IF NOT EXISTS '{username}'@'%' IDENTIFIED BY %s",
            (password,),
        )

    # (d) Grant exactly the five documented privileges. GRANT is idempotent, so
    #     it runs on every invocation to converge a partially-prepared account.
    run_sql(
        db,
        f"GRANT {', '.join(CDC_GRANTS)} ON *.* TO '{username}'@'%'",
    )

    # (e) Set the binary-log retention window (RDS-specific procedure). The hour
    #     count is a bound value.
    run_sql(
        db,
        "CALL mysql.rds_set_configuration('binlog retention hours', %s)",
        (inputs.binlog_retention_hours,),
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

        # Verify every precondition BEFORE any modification (Requirement 3.9).
        verify_preconditions(clients.db)

        # Create the CDC user, grant it, set retention, and publish its
        # credential. Idempotent and safe to re-run.
        create_cdc_user(clients, inputs)

        # Non-secret success summary: the user name and the parameter name
        # holding its credential — never a credential value (Requirement 3.13).
        print(
            "cdc-prepare-mariadb: prepared CDC user "
            f"{inputs.cdc_username!r}; credential resolved from parameters "
            f"{inputs.cdc_username_parameter!r} (username) and "
            f"{inputs.cdc_password_parameter!r} (password)"
        )
        return 0
    except InputError as exc:
        print(f"cdc-prepare-mariadb: {exc}", file=sys.stderr)
        return 2
    except PreconditionError as exc:
        print(f"cdc-prepare-mariadb: precondition failed: {exc}", file=sys.stderr)
        return 1
    except ConnectionError as exc:
        print(f"cdc-prepare-mariadb: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
