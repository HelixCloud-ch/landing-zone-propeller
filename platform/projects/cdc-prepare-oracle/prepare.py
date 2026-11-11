#!/usr/bin/env python3
"""Prepare an RDS for Oracle database for Debezium CDC (LogMiner).

Idempotent. Every run:

1. Reads the inputs (PROPELLER_INPUT_*) and the admin credential from the SSM
   parameter named by `admin_credential_parameter`.
2. If `enable_supplemental_logging` is true, turns on the supplemental logging
   that is missing (minimal and primary key). Then verifies the LogMiner
   preconditions. It changes nothing else if one fails.
3. Resolves the CDC credential from two SecureString parameters, one for the
   username and one for the password. An existing parameter is the source of
   truth and is never overwritten. A missing one is created: the username from
   `cdc_username`, the password generated.
4. Creates the CDC user if it does not exist, grants the LogMiner privileges,
   and sets the archived log retention.
5. Logs in as the CDC user, to prove that the password in SSM is the database
   password.

On RDS the master user is not SYS: privileges on SYS objects (packages, V_$
views) are granted with rdsadmin.rdsadmin_util.grant_sys_object.

Two scalar parameters, not one JSON document: the connector reads each with
the MSK Connect SSM config provider (`${ssm::<name>}`), which cannot read a key
out of a JSON document.

No credential value is ever printed. Not yet verified against a live instance
(see docs/cdc-deployment-verification.md).
"""

from __future__ import annotations

import json
import os
import re
import secrets
import sys
from dataclasses import dataclass

import boto3
import botocore.exceptions
import oracledb

PREFIX = "PROPELLER_INPUT_"

# System privileges and roles, granted with a plain GRANT.
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

# (SYS object, privilege), granted with rdsadmin_util.grant_sys_object.
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
    ("V_$MYSTAT", "SELECT"),
    ("V_$STATNAME", "SELECT"),
)

# Oracle DDL cannot bind values, so the username and the password are composed
# into CREATE USER / GRANT. The username must be a bare identifier (allowlist).
# The password goes in double quotes: it must not contain `"` and must fit in
# 30 bytes (Oracle 19c limit).
USERNAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_#$]{0,29}$")
# The default tablespace is read from the database, then composed into ALTER
# USER, so it must be a bare identifier too.
TABLESPACE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_#$]{0,127}$")
PASSWORD_MAX_BYTES = 30


class InputError(Exception):
    """A missing or malformed input. Exit code 2."""


class PrepareError(Exception):
    """A precondition or check failed on the database. Exit code 1."""


# ── Inputs ───────────────────────────────────────────────────────────────────


def _env(name: str, default: str | None = None) -> str:
    value = os.environ.get(PREFIX + name, "")
    if value:
        return value
    if default is None:
        raise InputError(f"missing required input: {PREFIX}{name}")
    return default


def _env_bool(name: str) -> bool:
    raw = _env(name, "false").lower()
    if raw not in ("true", "false"):
        raise InputError(f"input {PREFIX}{name} must be true or false, got {raw!r}")
    return raw == "true"


def _env_int(name: str, default: str | None = None) -> int:
    raw = _env(name, default)
    try:
        return int(raw)
    except ValueError:
        raise InputError(f"input {PREFIX}{name} must be an integer, got {raw!r}") from None


@dataclass(frozen=True)
class Inputs:
    db_host: str
    db_port: int
    service_name: str
    pdb_name: str  # empty for a non-CDB instance
    admin_credential_parameter: str
    admin_username: str  # used when the admin parameter holds only a password
    cdc_username: str
    cdc_username_parameter: str
    cdc_password_parameter: str
    archivelog_retention_hours: int
    kms_key_id: str
    enable_supplemental_logging: bool


def read_inputs() -> Inputs:
    return Inputs(
        db_host=_env("db_host"),
        db_port=_env_int("db_port", "1521"),
        service_name=_env("service_name"),
        pdb_name=_env("pdb_name", ""),
        admin_credential_parameter=_env("admin_credential_parameter"),
        admin_username=_env("admin_username", ""),
        cdc_username=_env("cdc_username"),
        cdc_username_parameter=_env("cdc_username_parameter"),
        cdc_password_parameter=_env("cdc_password_parameter"),
        archivelog_retention_hours=_env_int("archivelog_retention_hours"),
        kms_key_id=_env("kms_key_id", "alias/aws/ssm"),
        enable_supplemental_logging=_env_bool("enable_supplemental_logging"),
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


def generate_password() -> str:
    # 30 characters from [A-Za-z0-9_-]: fits Oracle's limit, safe in double quotes.
    return secrets.token_urlsafe(PASSWORD_MAX_BYTES)[:PASSWORD_MAX_BYTES]


def resolve_cdc_credential(ssm, inputs: Inputs) -> tuple[str, str]:
    username = get_or_create_parameter(
        ssm, inputs.cdc_username_parameter, lambda: inputs.cdc_username, inputs.kms_key_id
    )
    password = get_or_create_parameter(
        ssm, inputs.cdc_password_parameter, generate_password, inputs.kms_key_id
    )
    if not USERNAME_RE.match(username):
        raise InputError(
            f"CDC username in {inputs.cdc_username_parameter} must match {USERNAME_RE.pattern}"
        )
    if '"' in password or len(password.encode()) > PASSWORD_MAX_BYTES:
        raise InputError(
            f"CDC password in {inputs.cdc_password_parameter} must not contain '\"' "
            f"and must be at most {PASSWORD_MAX_BYTES} bytes"
        )
    return username.upper(), password


# ── Database ─────────────────────────────────────────────────────────────────


def connect(inputs: Inputs, user: str, password: str):
    """Thin mode (no Oracle client). On a CDB, connect to the PDB service."""
    conn = oracledb.connect(
        host=inputs.db_host, port=inputs.db_port, service_name=inputs.pdb_name or inputs.service_name,
        user=user, password=password, tcp_connect_timeout=10,
    )
    # rdsadmin procedures need a commit; DDL commits by itself.
    conn.autocommit = True
    return conn


def query(db, sql: str, params: dict | None = None) -> list[tuple]:
    with db.cursor() as cur:
        cur.execute(sql, params or {})
        return list(cur.fetchall()) if cur.description else []


def enable_supplemental_logging(db) -> None:
    """Turn on the supplemental logging that is missing, minimal and primary key.

    On RDS only rdsadmin_util can change it. Only missing settings are added,
    so a rerun changes nothing.
    """
    supp_min, supp_pk = (str(v).upper() for v in query(
        db, "SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK FROM V$DATABASE")[0])
    if supp_min not in ("YES", "IMPLICIT"):
        print("cdc-prepare-oracle: turning on minimal supplemental logging")
        query(db, "BEGIN rdsadmin.rdsadmin_util.alter_supplemental_logging(p_action => 'ADD'); END;")
    if supp_pk != "YES":
        print("cdc-prepare-oracle: turning on primary key supplemental logging")
        query(db, "BEGIN rdsadmin.rdsadmin_util.alter_supplemental_logging("
                  "p_action => 'ADD', p_type => 'PRIMARY KEY'); END;")


def verify_preconditions(db) -> None:
    """Fail before any change if LogMiner cannot feed Debezium."""
    # V$DATABASE is the public synonym; V_$DATABASE (the SYS view) needs a SYS. prefix.
    rows = query(db, "SELECT LOG_MODE, SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK FROM V$DATABASE")
    if not rows:
        raise PrepareError("cannot read V$DATABASE: the admin user may lack SELECT on it")
    log_mode, supp_min, supp_pk = (str(v).upper() for v in rows[0])
    if log_mode != "ARCHIVELOG":
        raise PrepareError(
            f"LOG_MODE is {log_mode}, not ARCHIVELOG. On RDS it is ARCHIVELOG when the "
            "automated backup retention (backup_retention_period) is greater than 0."
        )
    if supp_min not in ("YES", "IMPLICIT"):
        raise PrepareError(
            "minimal supplemental logging is off: run "
            "rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD')"
        )
    if supp_pk != "YES":
        raise PrepareError(
            "primary key supplemental logging is off: run "
            "rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD', 'PRIMARY KEY')"
        )


def prepare_user(db, username: str, password: str, inputs: Inputs) -> None:
    """Create the CDC user if absent, grant, and set the archived log retention.

    An existing user keeps its password: this project never rotates it. DDL
    cannot bind values: `username` is allowlisted and `password` was checked
    in resolve_cdc_credential (double-quoted, no `"`). PL/SQL calls bind.
    """
    exists = query(db, "SELECT COUNT(*) FROM ALL_USERS WHERE USERNAME = :u", {"u": username})[0][0]
    if not exists:
        query(db, f'CREATE USER {username} IDENTIFIED BY "{password}"')
    # The connector creates its LOG_MINING_FLUSH table in the user's default
    # tablespace and writes to it, so the user needs a quota there.
    tablespace = query(
        db, "SELECT DEFAULT_TABLESPACE FROM DBA_USERS WHERE USERNAME = :u", {"u": username},
    )[0][0]
    if not TABLESPACE_RE.match(tablespace):
        raise PrepareError(f"unexpected default tablespace name {tablespace!r}")
    query(db, f"ALTER USER {username} QUOTA UNLIMITED ON {tablespace}")
    for grant in CDC_SYSTEM_GRANTS:
        query(db, f"GRANT {grant} TO {username}")
    # grant_sys_object succeeds when the privilege is already granted.
    for obj, privilege in CDC_SYS_OBJECT_GRANTS:
        query(
            db,
            "BEGIN rdsadmin.rdsadmin_util.grant_sys_object("
            "p_obj_name => :obj, p_grantee => :grantee, p_privilege => :priv); END;",
            {"obj": obj, "grantee": username, "priv": privilege},
        )
    query(
        db,
        "BEGIN rdsadmin.rdsadmin_util.set_configuration("
        "name => 'archivelog retention hours', value => :hours); END;",
        {"hours": str(inputs.archivelog_retention_hours)},
    )


def verify_login(inputs: Inputs, username: str, password: str) -> None:
    """Log in as the CDC user. This finds a password that differs between the
    database and SSM (for example after the parameter was recreated)."""
    try:
        conn = connect(inputs, username, password)
    except oracledb.Error as exc:
        raise PrepareError(
            f"the CDC user {username!r} cannot log in with the password in "
            f"{inputs.cdc_password_parameter}: {exc}. Make them equal: change the "
            "database password, or the parameter."
        ) from None
    conn.close()


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
            if inputs.enable_supplemental_logging:
                enable_supplemental_logging(db)
            verify_preconditions(db)
            username, password = resolve_cdc_credential(ssm, inputs)
            prepare_user(db, username, password, inputs)
        finally:
            db.close()
        verify_login(inputs, username, password)
    except InputError as exc:
        print(f"cdc-prepare-oracle: {exc}", file=sys.stderr)
        return 2
    except (PrepareError, oracledb.Error, botocore.exceptions.BotoCoreError,
            botocore.exceptions.ClientError) as exc:
        print(f"cdc-prepare-oracle: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    print(
        f"cdc-prepare-oracle: CDC user {username!r} ready on {inputs.db_host}; credential in "
        f"{inputs.cdc_username_parameter} and {inputs.cdc_password_parameter}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
