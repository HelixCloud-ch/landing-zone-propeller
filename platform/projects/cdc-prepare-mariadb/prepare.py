#!/usr/bin/env python3
"""Prepare an RDS for MariaDB database for Debezium CDC.

Idempotent. Every run:

1. Reads the inputs (PROPELLER_INPUT_*) and the admin credential from the SSM
   parameter named by `admin_credential_parameter`.
2. Verifies the binary-log preconditions. It changes nothing if one fails.
3. Resolves the CDC credential from two SecureString parameters, one for the
   username and one for the password. An existing parameter is the source of
   truth and is never overwritten. A missing one is created: the username from
   `cdc_username`, the password generated.
4. Creates the CDC user if it does not exist, grants the Debezium privileges,
   and sets the binary-log retention.
5. Logs in as the CDC user, to prove that the password in SSM is the database
   password.

Two scalar parameters, not one JSON document: the connector reads each with
the MSK Connect SSM config provider (`${ssm::<name>}`), which cannot read a key
out of a JSON document.

No credential value is ever printed.
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
import pymysql

PREFIX = "PROPELLER_INPUT_"

# The privileges Debezium's MariaDB connector needs. RDS does not allow a global
# read lock, so the snapshot uses table locks, which need LOCK TABLES.
CDC_GRANTS = (
    "SELECT", "RELOAD", "SHOW DATABASES", "REPLICATION SLAVE", "REPLICATION CLIENT",
    "LOCK TABLES",
)

# MariaDB cannot bind an account name in CREATE USER / GRANT, so the name is
# composed into the statement. This allowlist is the injection defence.
USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{1,80}$")


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
    admin_credential_parameter: str
    admin_username: str  # used when the admin parameter holds only a password
    cdc_username: str
    cdc_username_parameter: str
    cdc_password_parameter: str
    binlog_retention_hours: int
    kms_key_id: str


def read_inputs() -> Inputs:
    return Inputs(
        db_host=_env("db_host"),
        db_port=_env_int("db_port", "3306"),
        admin_credential_parameter=_env("admin_credential_parameter"),
        admin_username=_env("admin_username", ""),
        cdc_username=_env("cdc_username"),
        cdc_username_parameter=_env("cdc_username_parameter"),
        cdc_password_parameter=_env("cdc_password_parameter"),
        binlog_retention_hours=_env_int("binlog_retention_hours"),
        kms_key_id=_env("kms_key_id", "alias/aws/ssm"),
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
    return pymysql.connect(
        host=inputs.db_host, port=inputs.db_port, user=user, password=password,
        connect_timeout=10, autocommit=True,
    )


def query(db, sql: str, params: tuple = ()) -> list[tuple]:
    with db.cursor() as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def verify_preconditions(db) -> None:
    """Fail before any change if the binary log cannot feed Debezium."""
    def variable(name: str) -> str | None:
        rows = query(db, "SHOW VARIABLES LIKE %s", (name,))
        return str(rows[0][1]).upper() if rows else None

    if variable("log_bin") != "ON":
        raise PrepareError(
            "binary logging is off (log_bin). On RDS it is on when the automated "
            "backup retention (backup_retention_period) is greater than 0."
        )
    if variable("binlog_format") != "ROW":
        raise PrepareError("binlog_format must be ROW (set it in the DB parameter group)")
    if variable("binlog_row_image") != "FULL":
        raise PrepareError("binlog_row_image must be FULL (set it in the DB parameter group)")
    # Not every MariaDB version has this variable; absent means not compressed.
    if variable("log_bin_compress") == "ON":
        raise PrepareError("log_bin_compress must be OFF: Debezium cannot read a compressed binary log")


def prepare_user(db, username: str, password: str, inputs: Inputs) -> None:
    """Create the CDC user if absent, grant, and set the binlog retention.

    IF NOT EXISTS leaves an existing user and its password unchanged: this
    project never rotates it. The username is allowlisted (USERNAME_RE); every
    value is bound. `%%` is a literal `%` (the driver formats with %).
    """
    query(db, f"CREATE USER IF NOT EXISTS '{username}'@'%%' IDENTIFIED BY %s", (password,))
    query(db, f"GRANT {', '.join(CDC_GRANTS)} ON *.* TO '{username}'@'%%'")
    query(db, "CALL mysql.rds_set_configuration('binlog retention hours', %s)",
          (inputs.binlog_retention_hours,))


def verify_login(inputs: Inputs, username: str, password: str) -> None:
    """Log in as the CDC user. This finds a password that differs between the
    database and SSM (for example after the parameter was recreated)."""
    try:
        conn = connect(inputs, username, password)
    except pymysql.MySQLError as exc:
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
            verify_preconditions(db)
            username, password = resolve_cdc_credential(ssm, inputs)
            prepare_user(db, username, password, inputs)
        finally:
            db.close()
        verify_login(inputs, username, password)
    except InputError as exc:
        print(f"cdc-prepare-mariadb: {exc}", file=sys.stderr)
        return 2
    except (PrepareError, pymysql.MySQLError, botocore.exceptions.BotoCoreError,
            botocore.exceptions.ClientError) as exc:
        print(f"cdc-prepare-mariadb: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    print(
        f"cdc-prepare-mariadb: CDC user {username!r} ready on {inputs.db_host}; credential in "
        f"{inputs.cdc_username_parameter} and {inputs.cdc_password_parameter}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
