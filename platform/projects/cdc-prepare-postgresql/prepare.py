#!/usr/bin/env python3
"""Prepare an RDS for PostgreSQL database for Debezium CDC.

Idempotent. Every run:

1. Reads the inputs (PROPELLER_INPUT_*) and the admin credential from the SSM
   parameter named by `admin_credential_parameter`.
2. Verifies the logical-replication preconditions and plans the publication.
   It changes nothing if one fails.
3. Resolves the CDC credential from two SecureString parameters, one for the
   username and one for the password. An existing parameter is the source of
   truth and is never overwritten. A missing one is created: the username from
   `cdc_username`, the password generated.
4. Creates the CDC role if it does not exist, grants the Debezium privileges,
   and (if `manage_publication` is true) creates or syncs the publication.
5. Logs in as the CDC user, to prove that the password in SSM is the database
   password.

Two scalar parameters, not one JSON document: the connector reads each with
the MSK Connect SSM config provider (`${ssm::<name>}`), which cannot read a key
out of a JSON document.

The replication slot is created by the connector, not by this script. The
script only reports its state.

No credential value is ever printed.
"""

from __future__ import annotations

import json
import os
import re
import secrets
import sys
from dataclasses import dataclass
from pathlib import Path

import boto3
import botocore.exceptions
import psycopg
from psycopg import sql

PREFIX = "PROPELLER_INPUT_"
NAME = "cdc-prepare-postgresql"

SSL_MODES = ("disable", "allow", "prefer", "require", "verify-ca", "verify-full")

# PostgreSQL cannot bind an identifier or a password in CREATE ROLE / GRANT, so
# they are composed into the statement. The allowlists are the first defence;
# psycopg.sql.Identifier and sql.Literal quote them in the second layer.
USERNAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,62}$")
IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]{0,62}$")
SLOT_NAME_RE = re.compile(r"^[a-z0-9_]{1,63}$")

# These values of log_statement write CREATE ROLE ... PASSWORD to the database log.
LOGGING_PASSWORD_VALUES = ("ddl", "mod", "all")


class InputError(Exception):
    """A missing or malformed input. Exit code 2."""


class PrepareError(Exception):
    """A precondition or check failed on the database. Exit code 1."""


def log(message: str) -> None:
    print(f"{NAME}: {message}")


def warn(message: str) -> None:
    print(f"{NAME}: warning: {message}", file=sys.stderr)


# ── Inputs ───────────────────────────────────────────────────────────────────


def _env(name: str, default: str | None = None) -> str:
    value = os.environ.get(PREFIX + name, "")
    if value:
        return value
    if default is None:
        raise InputError(f"missing required input: {PREFIX}{name}")
    return default


def _env_int(name: str, default: str | None = None) -> int:
    raw = _env(name, default)
    try:
        return int(raw)
    except ValueError:
        raise InputError(f"input {PREFIX}{name} must be an integer, got {raw!r}") from None


def _env_bool(name: str, default: str) -> bool:
    raw = _env(name, default)
    if raw not in ("true", "false"):
        raise InputError(f"input {PREFIX}{name} must be true or false, got {raw!r}")
    return raw == "true"


def _env_list(name: str, default: str) -> list[str]:
    raw = _env(name, default)
    try:
        doc = json.loads(raw)
    except ValueError as exc:
        raise InputError(f"input {PREFIX}{name} is not valid JSON: {exc}") from None
    if not isinstance(doc, list) or not all(isinstance(item, str) and item for item in doc):
        raise InputError(f"input {PREFIX}{name} must be a JSON list of non-empty strings")
    return doc


def _identifier(name: str, value: str, pattern: re.Pattern = IDENTIFIER_RE) -> str:
    if not pattern.match(value):
        raise InputError(f"{name} {value!r} must match {pattern.pattern}")
    return value


def _table(value: str) -> tuple[str, str]:
    schema, dot, table = value.partition(".")
    if not dot:
        raise InputError(f"publication table {value!r} must be schema.table")
    return (
        _identifier("publication table schema", schema),
        _identifier("publication table name", table),
    )


@dataclass(frozen=True)
class Inputs:
    db_host: str
    db_port: int
    db_name: str
    admin_credential_parameter: str
    admin_username: str  # used when the admin parameter holds only a password
    cdc_username: str
    cdc_username_parameter: str
    cdc_password_parameter: str
    kms_key_id: str
    schemas: tuple[str, ...]
    publication_name: str
    publication_tables: tuple[tuple[str, str], ...]
    manage_publication: bool
    slot_name: str
    ssl_mode: str
    ssl_root_cert: str


def read_inputs() -> Inputs:
    ssl_mode = _env("ssl_mode", "require")
    if ssl_mode not in SSL_MODES:
        raise InputError(f"input {PREFIX}ssl_mode must be one of {', '.join(SSL_MODES)}, got {ssl_mode!r}")
    ssl_root_cert = _env("ssl_root_cert", "")
    if ssl_mode in ("verify-ca", "verify-full"):
        root_cert = ssl_root_cert or os.environ.get("PGSSLROOTCERT", "")
        if not root_cert:
            raise InputError(
                f"ssl_mode {ssl_mode} needs a CA bundle: set {PREFIX}ssl_root_cert or PGSSLROOTCERT"
            )
        if not Path(root_cert).is_file():
            raise InputError(f"the CA bundle {root_cert!r} for ssl_mode {ssl_mode} does not exist")

    manage_publication = _env_bool("manage_publication", "true")
    publication_tables = tuple(_table(t) for t in _env_list("publication_tables", "[]"))
    if publication_tables and not manage_publication:
        raise InputError(
            f"{PREFIX}publication_tables needs {PREFIX}manage_publication=true"
        )
    schemas = tuple(_identifier("schema", s) for s in _env_list("schemas", '["public"]'))
    if not schemas:
        raise InputError(f"input {PREFIX}schemas must list at least one schema")

    return Inputs(
        db_host=_env("db_host"),
        db_port=_env_int("db_port", "5432"),
        db_name=_env("db_name"),
        admin_credential_parameter=_env("admin_credential_parameter"),
        admin_username=_env("admin_username", ""),
        cdc_username=_env("cdc_username"),
        cdc_username_parameter=_env("cdc_username_parameter"),
        cdc_password_parameter=_env("cdc_password_parameter"),
        kms_key_id=_env("kms_key_id", "alias/aws/ssm"),
        schemas=schemas,
        publication_name=_identifier("publication_name", _env("publication_name", "dbz_publication")),
        publication_tables=publication_tables,
        manage_publication=manage_publication,
        slot_name=_identifier("slot_name", _env("slot_name", "debezium"), SLOT_NAME_RE),
        ssl_mode=ssl_mode,
        ssl_root_cert=ssl_root_cert,
    )


# ── SSM ──────────────────────────────────────────────────────────────────────


def ssm_client():
    return boto3.client("ssm")


def read_admin_credential(ssm, parameter: str, admin_username: str) -> tuple[str, str]:
    """Return (username, password) from the admin parameter.

    The value is either a JSON document {"username": ..., "password": ...} or
    the password alone. For the password alone, the username comes from the
    `admin_username` input.
    """
    value = ssm.get_parameter(Name=parameter, WithDecryption=True)["Parameter"]["Value"]
    try:
        doc = json.loads(value)
    except ValueError:
        doc = None
    if isinstance(doc, dict) and "username" in doc and "password" in doc:
        return str(doc["username"]), str(doc["password"])
    if not admin_username:
        raise InputError(
            f"{parameter} holds only a password: set {PREFIX}admin_username, "
            'or store {"username": ..., "password": ...}'
        )
    return admin_username, value


def get_or_create_parameter(ssm, name: str, make_value, kms_key_id: str) -> str:
    """Return the parameter's value. If it does not exist, create it with
    make_value() as a SecureString. An existing parameter is never changed."""
    try:
        return ssm.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        value = make_value()
        ssm.put_parameter(Name=name, Value=value, Type="SecureString", KeyId=kms_key_id)
        return value


def resolve_cdc_credential(ssm, inputs: Inputs) -> tuple[str, str]:
    username = get_or_create_parameter(
        ssm, inputs.cdc_username_parameter, lambda: inputs.cdc_username, inputs.kms_key_id
    )
    password = get_or_create_parameter(
        ssm, inputs.cdc_password_parameter, lambda: secrets.token_urlsafe(32), inputs.kms_key_id
    )
    if not USERNAME_RE.match(username):
        raise InputError(
            f"CDC username in {inputs.cdc_username_parameter} must match {USERNAME_RE.pattern}"
        )
    return username, password


# ── Database ─────────────────────────────────────────────────────────────────


def connect(inputs: Inputs, user: str, password: str):
    options = {"sslrootcert": inputs.ssl_root_cert} if inputs.ssl_root_cert else {}
    return psycopg.connect(
        host=inputs.db_host, port=inputs.db_port, dbname=inputs.db_name,
        user=user, password=password, connect_timeout=10, autocommit=True,
        sslmode=inputs.ssl_mode, **options,
    )


def query(db, statement, params=None) -> list[tuple]:
    with db.cursor() as cur:
        cur.execute(statement, params)
        return list(cur.fetchall()) if cur.description else []


def one_value(db, statement, params=None):
    rows = query(db, statement, params)
    return rows[0][0] if rows else None


SETTING = "SELECT current_setting(%s, true)"
SLOT = (
    "SELECT slot_type, plugin, database, active, "
    "pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) "
    "FROM pg_replication_slots WHERE slot_name = %s"
)
SLOTS_IN_USE = "SELECT count(*) FROM pg_replication_slots"
WAL_SENDERS_IN_USE = "SELECT count(*) FROM pg_stat_replication"
PUBLICATION = "SELECT puballtables FROM pg_publication WHERE pubname = %s"
PUBLICATION_TABLES = "SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname = %s"
MISSING_TABLES = (
    "SELECT t.s, t.t FROM unnest(%s::text[], %s::text[]) AS t(s, t) "
    "WHERE NOT EXISTS (SELECT 1 FROM pg_tables p WHERE p.schemaname = t.s AND p.tablename = t.t)"
)
# Tables without a primary key and with replica identity default or nothing
# refuse UPDATE and DELETE once a publication publishes them.
_NO_KEY = (
    "SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
    "WHERE c.relkind = 'r' AND c.relreplident IN ('d', 'n') "
    "AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.oid AND i.indisprimary) "
)
NO_KEY_TABLES_ALL = (
    _NO_KEY + "AND n.nspname NOT IN ('pg_catalog', 'information_schema') "
    "AND left(n.nspname, 8) <> 'pg_toast' ORDER BY 1, 2"
)
NO_KEY_TABLES_LISTED = (
    _NO_KEY + "AND (n.nspname, c.relname) IN (SELECT * FROM unnest(%s::text[], %s::text[])) ORDER BY 1, 2"
)
ROLE_EXISTS = "SELECT 1 FROM pg_roles WHERE rolname = %s"


def verify_preconditions(db, inputs: Inputs) -> None:
    """Fail before any change if logical replication cannot feed Debezium.
    Report the settings that need attention but do not stop the run."""

    def setting(name: str) -> str | None:
        return one_value(db, SETTING, (name,))

    wal_level = setting("wal_level")
    rds_logical = setting("rds.logical_replication")
    if wal_level != "logical":
        if rds_logical == "on":
            raise PrepareError(
                f"wal_level is {wal_level!r} although rds.logical_replication is on: "
                "reboot the DB instance to apply it"
            )
        raise PrepareError(
            f"wal_level must be logical, it is {wal_level!r}. Set rds.logical_replication=1 "
            "in the DB parameter group (static), then reboot the DB instance."
        )

    slot_rows = query(db, SLOT, (inputs.slot_name,))
    slots_in_use = int(one_value(db, SLOTS_IN_USE))
    max_slots = int(setting("max_replication_slots"))
    if slot_rows:
        slot_type, plugin, database, active, retained = slot_rows[0]
        if slot_type != "logical" or plugin != "pgoutput" or database != inputs.db_name:
            raise PrepareError(
                f"the replication slot {inputs.slot_name!r} exists but Debezium cannot use it "
                f"(type {slot_type}, plugin {plugin}, database {database}): it must be a "
                f"pgoutput slot on database {inputs.db_name!r}. Use another slot_name."
            )
        report_slot(inputs.slot_name, active, retained)
    elif slots_in_use >= max_slots:
        raise PrepareError(
            f"no free replication slot: {slots_in_use} of max_replication_slots={max_slots} in use, "
            f"and the slot {inputs.slot_name!r} does not exist. Raise max_replication_slots "
            "in the DB parameter group (static), then reboot."
        )

    senders_in_use = int(one_value(db, WAL_SENDERS_IN_USE))
    log(
        f"rds.logical_replication={rds_logical}, wal_level={wal_level}, "
        f"replication slots {slots_in_use}/{max_slots}, "
        f"WAL senders {senders_in_use}/{setting('max_wal_senders')} (count includes physical replicas)"
    )
    if setting("max_slot_wal_keep_size") == "-1":
        warn(
            "max_slot_wal_keep_size is -1: an unread replication slot keeps WAL without a limit "
            "and can fill the storage. Set it in the DB parameter group if the instance allows."
        )
    if setting("log_statement") in LOGGING_PASSWORD_VALUES:
        warn(
            "log_statement logs DDL: CREATE ROLE ... PASSWORD can reach the database log. "
            "Use log_statement=none if that is not acceptable."
        )
    if int(setting("server_version_num") or 0) < 100000:
        warn("PostgreSQL older than 10 has no pgoutput plugin")


def report_slot(slot_name: str, active: bool, retained: int | None) -> None:
    state = "active" if active else "inactive"
    amount = "unknown" if retained is None else f"{int(retained)} bytes"
    log(f"replication slot {slot_name!r}: {state}, retained WAL {amount}")
    if not active and retained:
        warn(
            f"the replication slot {slot_name!r} is inactive and keeps {int(retained)} bytes of WAL. "
            "An unread slot can fill the storage."
        )


@dataclass(frozen=True)
class PublicationPlan:
    action: str  # "none", "create" or "alter"
    tables: tuple[tuple[str, str], ...] = ()


def _split(tables) -> tuple[list[str], list[str]]:
    return [s for s, _ in tables], [t for _, t in tables]


def plan_publication(db, inputs: Inputs) -> PublicationPlan:
    """Decide what the publication needs. Changes nothing; fails when it
    cannot be created or changed safely."""
    name = inputs.publication_name
    row = query(db, PUBLICATION, (name,))
    if not inputs.manage_publication:
        if row:
            log(f"publication {name!r} exists (not managed by this run)")
        else:
            log(
                f"publication {name!r} does not exist and this run does not create it: "
                "the DBA or the connector must create it"
            )
        return PublicationPlan("none")

    wanted = set(inputs.publication_tables)
    if wanted:
        schemas, tables = _split(inputs.publication_tables)
        missing = query(db, MISSING_TABLES, (schemas, tables))
        if missing:
            raise PrepareError(
                "publication_tables not found in the database: "
                + ", ".join(f"{s}.{t}" for s, t in missing)
            )

    if row:
        all_tables = bool(row[0][0])
        if all_tables != (not wanted):
            raise PrepareError(
                f"publication {name!r} exists as "
                f"{'FOR ALL TABLES' if all_tables else 'a table list'} and cannot be switched to "
                f"{'a table list' if wanted else 'FOR ALL TABLES'}. Drop it "
                f"(DROP PUBLICATION {name}), or change publication_tables."
            )
        current = {(s, t) for s, t in query(db, PUBLICATION_TABLES, (name,))}
        if all_tables or current == wanted:
            schemas, tables = _split(sorted(current))
            keyless = query(db, NO_KEY_TABLES_LISTED, (schemas, tables))
            if keyless:
                warn(_keyless_message(keyless, "already published"))
            return PublicationPlan("none")
        action = "alter"
    else:
        action = "create"

    if wanted:
        keyless = query(db, NO_KEY_TABLES_LISTED, _split(inputs.publication_tables))
    else:
        keyless = query(db, NO_KEY_TABLES_ALL)
    if keyless:
        raise PrepareError(
            _keyless_message(keyless, f"to publish in {name!r}")
            + " Add a primary key, or run ALTER TABLE ... REPLICA IDENTITY FULL, then run again."
        )
    return PublicationPlan(action, tuple(sorted(wanted)))


def _keyless_message(tables: list[tuple], what: str) -> str:
    names = ", ".join(f"{s}.{t}" for s, t in tables)
    return (
        f"tables {what} with no primary key and replica identity default or nothing: {names}. "
        "UPDATE and DELETE on them fail while they are published."
    )


def prepare_user(db, username: str, password: str, inputs: Inputs) -> None:
    """Create the CDC role if absent and grant the Debezium privileges.

    An existing role and its password stay unchanged: this project never
    rotates it. Identifiers and the password are quoted by psycopg.sql; every
    other value is bound.
    """
    user = sql.Identifier(username)
    if not query(db, ROLE_EXISTS, (username,)):
        query(db, sql.SQL("CREATE ROLE {} WITH LOGIN PASSWORD {}").format(user, sql.Literal(password)))
    query(db, sql.SQL("GRANT rds_replication TO {}").format(user))
    for schema in inputs.schemas:
        query(db, sql.SQL("GRANT USAGE ON SCHEMA {} TO {}").format(sql.Identifier(schema), user))
        query(db, sql.SQL("GRANT SELECT ON ALL TABLES IN SCHEMA {} TO {}").format(sql.Identifier(schema), user))


def apply_publication(db, inputs: Inputs, plan: PublicationPlan) -> None:
    name = sql.Identifier(inputs.publication_name)
    tables = sql.SQL(", ").join(sql.Identifier(s, t) for s, t in plan.tables)
    if plan.action == "create" and plan.tables:
        query(db, sql.SQL("CREATE PUBLICATION {} FOR TABLE {}").format(name, tables))
    elif plan.action == "create":
        query(db, sql.SQL("CREATE PUBLICATION {} FOR ALL TABLES").format(name))
    elif plan.action == "alter":
        query(db, sql.SQL("ALTER PUBLICATION {} SET TABLE {}").format(name, tables))
    if plan.action != "none":
        done = {"create": "created", "alter": "synced"}[plan.action]
        log(f"publication {inputs.publication_name!r} {done}")


def verify_login(inputs: Inputs, username: str, password: str) -> None:
    """Log in as the CDC user. This finds a password that differs between the
    database and SSM (for example after the parameter was recreated)."""
    try:
        conn = connect(inputs, username, password)
    except psycopg.Error as exc:
        raise PrepareError(
            f"the CDC user {username!r} cannot log in with the password in "
            f"{inputs.cdc_password_parameter}: {_one_line(exc)}. Make them equal: change the "
            "database password, or the parameter."
        ) from None
    conn.close()


def _one_line(exc: Exception) -> str:
    text = str(exc).strip()
    return text.splitlines()[0] if text else type(exc).__name__


# ── Main ─────────────────────────────────────────────────────────────────────


def main() -> int:
    try:
        inputs = read_inputs()
        ssm = ssm_client()
        admin_user, admin_password = read_admin_credential(
            ssm, inputs.admin_credential_parameter, inputs.admin_username
        )
        db = connect(inputs, admin_user, admin_password)
        try:
            verify_preconditions(db, inputs)
            plan = plan_publication(db, inputs)
            username, password = resolve_cdc_credential(ssm, inputs)
            prepare_user(db, username, password, inputs)
            apply_publication(db, inputs, plan)
        finally:
            db.close()
        verify_login(inputs, username, password)
    except InputError as exc:
        print(f"{NAME}: {exc}", file=sys.stderr)
        return 2
    except (PrepareError, psycopg.Error, botocore.exceptions.BotoCoreError,
            botocore.exceptions.ClientError) as exc:
        print(f"{NAME}: {type(exc).__name__}: {_one_line(exc)}", file=sys.stderr)
        return 1

    log(
        f"CDC user {username!r} ready on {inputs.db_host}/{inputs.db_name}; credential in "
        f"{inputs.cdc_username_parameter} and {inputs.cdc_password_parameter}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
