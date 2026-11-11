"""Tests for cdc-prepare-mariadb/prepare.py, with fake SSM and database clients.

Run: uv run --project platform/shared/python/cdc pytest platform/projects/cdc-prepare-mariadb
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pymysql
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import prepare  # noqa: E402

SECRET = "s3cr3t-admin-pw"

@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    """Tests see only the inputs they set."""
    for key in list(os.environ):
        if key.startswith("PROPELLER_INPUT_"):
            monkeypatch.delenv(key)


GOOD_VARIABLES = {"log_bin": "ON", "binlog_format": "ROW", "binlog_row_image": "FULL"}


class FakeSSM:
    class exceptions:
        class ParameterNotFound(Exception):
            pass

    def __init__(self, params: dict[str, str]):
        self.params = dict(params)
        self.puts: list[dict] = []

    def get_parameter(self, Name, WithDecryption):
        assert WithDecryption
        if Name not in self.params:
            raise self.exceptions.ParameterNotFound(Name)
        return {"Parameter": {"Value": self.params[Name]}}

    def put_parameter(self, **kwargs):
        self.puts.append(kwargs)
        self.params[kwargs["Name"]] = kwargs["Value"]


class FakeCursor:
    def __init__(self, db):
        self.db = db
        self.rows: list[tuple] = []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, sql, params=()):
        self.db.executed.append((sql, params))
        self.rows = []
        if sql.startswith("SHOW VARIABLES"):
            value = self.db.variables.get(params[0])
            self.rows = [(params[0], value)] if value is not None else []

    def fetchall(self):
        return self.rows


class FakeDB:
    def __init__(self, variables=GOOD_VARIABLES):
        self.variables = dict(variables)
        self.executed: list[tuple] = []
        self.closed = False

    def cursor(self):
        return FakeCursor(self)

    def close(self):
        self.closed = True

    def statements(self):
        return [sql for sql, _ in self.executed if not sql.startswith("SHOW")]


ENV = {
    "db_host": "db.example.internal",
    "admin_credential_parameter": "/db/admin",
    "cdc_username": "cdc_user",
    "cdc_username_parameter": "/db/cdc-username",
    "cdc_password_parameter": "/db/cdc-password",
    "binlog_retention_hours": "168",
}


@pytest.fixture
def env(monkeypatch):
    for key, value in ENV.items():
        monkeypatch.setenv(prepare.PREFIX + key, value)
    return monkeypatch


def run_main(monkeypatch, ssm, admin_db, login_error=None):
    """Run main() with fakes. Returns (exit code, connect calls)."""
    calls = []

    def connect(inputs, user, password):
        calls.append((user, password))
        if len(calls) == 1:
            return admin_db
        if login_error:
            raise login_error
        return FakeDB()

    monkeypatch.setattr(prepare, "ssm_client", lambda: ssm)
    monkeypatch.setattr(prepare, "connect", connect)
    return prepare.main(), calls


# ── Inputs ───────────────────────────────────────────────────────────────────


def test_inputs_defaults(env):
    inputs = prepare.read_inputs()
    assert inputs.db_port == 3306
    assert inputs.kms_key_id == "alias/aws/ssm"
    assert inputs.admin_username == ""


@pytest.mark.parametrize("name", ["db_host", "admin_credential_parameter", "binlog_retention_hours"])
def test_missing_required_input_exits_2(env, name, capsys):
    env.delenv(prepare.PREFIX + name)
    assert prepare.main() == 2
    assert prepare.PREFIX + name in capsys.readouterr().err


def test_non_integer_input_is_rejected(env):
    env.setenv(prepare.PREFIX + "db_port", "abc")
    with pytest.raises(prepare.InputError, match="must be an integer"):
        prepare.read_inputs()


# ── Admin credential ─────────────────────────────────────────────────────────


def test_admin_credential_json_document():
    ssm = FakeSSM({"/db/admin": '{"username": "admin", "password": "pw"}'})
    assert prepare.read_admin_credential(ssm, "/db/admin", "") == ("admin", "pw")


def test_admin_credential_password_only_uses_admin_username():
    ssm = FakeSSM({"/db/admin": "pw"})
    assert prepare.read_admin_credential(ssm, "/db/admin", "master") == ("master", "pw")


def test_admin_credential_password_only_without_admin_username_is_an_error():
    ssm = FakeSSM({"/db/admin": "pw"})
    with pytest.raises(prepare.InputError, match="admin_username"):
        prepare.read_admin_credential(ssm, "/db/admin", "")


# ── CDC credential ───────────────────────────────────────────────────────────


def test_missing_parameters_are_created(env):
    ssm = FakeSSM({})
    username, password = prepare.resolve_cdc_credential(ssm, prepare.read_inputs())
    assert username == "cdc_user" and len(password) >= 32
    assert [(p["Name"], p["Type"], p["KeyId"]) for p in ssm.puts] == [
        ("/db/cdc-username", "SecureString", "alias/aws/ssm"),
        ("/db/cdc-password", "SecureString", "alias/aws/ssm"),
    ]


def test_existing_parameters_are_the_source_of_truth(env):
    ssm = FakeSSM({"/db/cdc-username": "other_user", "/db/cdc-password": "kept"})
    assert prepare.resolve_cdc_credential(ssm, prepare.read_inputs()) == ("other_user", "kept")
    assert ssm.puts == []


def test_unsafe_username_is_rejected(env):
    ssm = FakeSSM({"/db/cdc-username": "x'@'%' --", "/db/cdc-password": "p"})
    with pytest.raises(prepare.InputError, match="must match"):
        prepare.resolve_cdc_credential(ssm, prepare.read_inputs())


# ── Database ─────────────────────────────────────────────────────────────────


def test_good_preconditions_pass():
    prepare.verify_preconditions(FakeDB())


@pytest.mark.parametrize("variable, value, message", [
    ("log_bin", "OFF", "backup_retention_period"),
    ("binlog_format", "MIXED", "ROW"),
    ("binlog_row_image", "MINIMAL", "FULL"),
    ("log_bin_compress", "ON", "compressed"),
])
def test_bad_precondition_fails(variable, value, message):
    with pytest.raises(prepare.PrepareError, match=message):
        prepare.verify_preconditions(FakeDB({**GOOD_VARIABLES, variable: value}))


def test_prepare_user_binds_password_and_grants(env):
    db = FakeDB()
    prepare.prepare_user(db, "cdc_user", "pw'; DROP", prepare.read_inputs())
    create, grant, retention = db.executed
    assert create == ("CREATE USER IF NOT EXISTS 'cdc_user'@'%%' IDENTIFIED BY %s", ("pw'; DROP",))
    assert grant[0] == "GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT, LOCK TABLES ON *.* TO 'cdc_user'@'%%'"
    assert retention == ("CALL mysql.rds_set_configuration('binlog retention hours', %s)", (168,))


# ── main ─────────────────────────────────────────────────────────────────────


def test_main_prepares_and_verifies_login(env, capsys):
    env.setenv(prepare.PREFIX + "admin_username", "master")
    ssm = FakeSSM({"/db/admin": SECRET})
    admin_db = FakeDB()
    code, calls = run_main(env, ssm, admin_db)
    assert code == 0
    assert calls[0] == ("master", SECRET)
    assert calls[1] == ("cdc_user", ssm.params["/db/cdc-password"])
    assert admin_db.closed
    out = capsys.readouterr()
    for secret in (SECRET, ssm.params["/db/cdc-password"]):
        assert secret not in out.out + out.err


def test_main_changes_nothing_when_a_precondition_fails(env):
    env.setenv(prepare.PREFIX + "admin_username", "master")
    ssm = FakeSSM({"/db/admin": SECRET})
    admin_db = FakeDB({**GOOD_VARIABLES, "log_bin": "OFF"})
    code, _ = run_main(env, ssm, admin_db)
    assert code == 1
    assert ssm.puts == [] and admin_db.statements() == []


def test_main_reports_a_password_that_differs_from_ssm(env, capsys):
    env.setenv(prepare.PREFIX + "admin_username", "master")
    ssm = FakeSSM({"/db/admin": SECRET, "/db/cdc-username": "cdc_user", "/db/cdc-password": "stale"})
    code, _ = run_main(env, ssm, FakeDB(), login_error=pymysql.err.OperationalError(1045, "Access denied"))
    assert code == 1
    err = capsys.readouterr().err
    assert "cannot log in with the password in /db/cdc-password" in err
    assert "stale" not in err


def test_main_reports_a_driver_error_without_traceback(env, monkeypatch, capsys):
    env.setenv(prepare.PREFIX + "admin_username", "master")

    def refuse(*_args):
        raise pymysql.err.OperationalError(2003, "Can't connect")

    monkeypatch.setattr(prepare, "ssm_client", lambda: FakeSSM({"/db/admin": SECRET}))
    monkeypatch.setattr(prepare, "connect", refuse)
    assert prepare.main() == 1
    assert "OperationalError" in capsys.readouterr().err
