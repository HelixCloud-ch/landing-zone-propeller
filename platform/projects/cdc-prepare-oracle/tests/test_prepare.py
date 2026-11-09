"""Tests for cdc-prepare-oracle/prepare.py, with fake SSM and database clients.

Run: uv run --project platform/shared/python/cdc pytest platform/projects/cdc-prepare-oracle
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import oracledb
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

GOOD_DATABASE = ("ARCHIVELOG", "YES", "YES")


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
        self.description = None
        self.rows: list[tuple] = []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, sql, params=None):
        self.db.executed.append((sql, params))
        self.description, self.rows = None, []
        if "FROM V$DATABASE" in sql:
            self.description, self.rows = [("x",)], [self.db.database]
        elif "FROM ALL_USERS" in sql:
            self.description, self.rows = [("x",)], [(1 if self.db.user_exists else 0,)]

    def fetchall(self):
        return self.rows


class FakeDB:
    def __init__(self, database=GOOD_DATABASE, user_exists=False):
        self.database = database
        self.user_exists = user_exists
        self.executed: list[tuple] = []
        self.closed = False

    def cursor(self):
        return FakeCursor(self)

    def close(self):
        self.closed = True

    def statements(self):
        return [sql for sql, _ in self.executed if not sql.startswith("SELECT")]


ENV = {
    "db_host": "db.example.internal",
    "service_name": "ORCL",
    "admin_credential_parameter": "/db/admin",
    "cdc_username": "cdc_user",
    "cdc_username_parameter": "/db/cdc-username",
    "cdc_password_parameter": "/db/cdc-password",
    "archivelog_retention_hours": "24",
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


# ── Inputs and credentials ───────────────────────────────────────────────────


def test_inputs_defaults(env):
    inputs = prepare.read_inputs()
    assert (inputs.db_port, inputs.pdb_name, inputs.kms_key_id) == (1521, "", "alias/aws/ssm")


@pytest.mark.parametrize("name", ["service_name", "archivelog_retention_hours"])
def test_missing_required_input_exits_2(env, name, capsys):
    env.delenv(prepare.PREFIX + name)
    assert prepare.main() == 2
    assert prepare.PREFIX + name in capsys.readouterr().err


def test_admin_credential_forms():
    assert prepare.read_admin_credential(
        FakeSSM({"/a": '{"username": "admin", "password": "pw"}'}), "/a", "") == ("admin", "pw")
    assert prepare.read_admin_credential(FakeSSM({"/a": "pw"}), "/a", "master") == ("master", "pw")
    with pytest.raises(prepare.InputError, match="admin_username"):
        prepare.read_admin_credential(FakeSSM({"/a": "pw"}), "/a", "")


def test_generated_password_fits_oracle(env):
    ssm = FakeSSM({})
    username, password = prepare.resolve_cdc_credential(ssm, prepare.read_inputs())
    assert username == "CDC_USER"
    assert len(password) == 30 and '"' not in password
    assert [p["Name"] for p in ssm.puts] == ["/db/cdc-username", "/db/cdc-password"]


def test_existing_parameters_are_the_source_of_truth(env):
    ssm = FakeSSM({"/db/cdc-username": "other", "/db/cdc-password": "kept"})
    assert prepare.resolve_cdc_credential(ssm, prepare.read_inputs()) == ("OTHER", "kept")
    assert ssm.puts == []


@pytest.mark.parametrize("username, password, message", [
    ("cdc user; DROP", "pw", "must match"),
    ("cdc", 'pw"; DROP', "must not contain"),
    ("cdc", "x" * 31, "at most 30 bytes"),
])
def test_unsafe_credential_is_rejected(env, username, password, message):
    ssm = FakeSSM({"/db/cdc-username": username, "/db/cdc-password": password})
    with pytest.raises(prepare.InputError, match=message):
        prepare.resolve_cdc_credential(ssm, prepare.read_inputs())


# ── Database ─────────────────────────────────────────────────────────────────


@pytest.mark.parametrize("database, message", [
    (("NOARCHIVELOG", "YES", "YES"), "backup_retention_period"),
    (("ARCHIVELOG", "NO", "YES"), "alter_supplemental_logging\\('ADD'\\)"),
    (("ARCHIVELOG", "YES", "NO"), "PRIMARY KEY"),
])
def test_bad_precondition_fails(database, message):
    with pytest.raises(prepare.PrepareError, match=message):
        prepare.verify_preconditions(FakeDB(database))


def test_implicit_minimal_logging_passes():
    prepare.verify_preconditions(FakeDB(("ARCHIVELOG", "IMPLICIT", "YES")))


def test_prepare_user_creates_with_double_quoted_password(env):
    db = FakeDB()
    prepare.prepare_user(db, "CDC_USER", "Ab_1-x", prepare.read_inputs())
    statements = db.statements()
    assert statements[0] == 'CREATE USER CDC_USER IDENTIFIED BY "Ab_1-x"'
    assert sum(s.startswith("GRANT ") for s in statements) == len(prepare.CDC_SYSTEM_GRANTS)
    sys_grants = [p for s, p in db.executed if "grant_sys_object" in s]
    assert len(sys_grants) == len(prepare.CDC_SYS_OBJECT_GRANTS)
    assert sys_grants[0] == {"obj": "DBMS_LOGMNR", "grantee": "CDC_USER", "priv": "EXECUTE"}
    assert db.executed[-1][1] == {"hours": "24"}


def test_existing_user_keeps_its_password(env):
    db = FakeDB(user_exists=True)
    prepare.prepare_user(db, "CDC_USER", "pw", prepare.read_inputs())
    assert not any(s.startswith("CREATE USER") for s in db.statements())


# ── main ─────────────────────────────────────────────────────────────────────


def test_main_prepares_and_verifies_login(env, capsys):
    ssm = FakeSSM({"/db/admin": '{"username": "admin", "password": "%s"}' % SECRET})
    admin_db = FakeDB()
    code, calls = run_main(env, ssm, admin_db)
    assert code == 0
    assert calls[0] == ("admin", SECRET)
    assert calls[1] == ("CDC_USER", ssm.params["/db/cdc-password"])
    assert admin_db.closed
    out = capsys.readouterr()
    for secret in (SECRET, ssm.params["/db/cdc-password"]):
        assert secret not in out.out + out.err


def test_main_changes_nothing_when_a_precondition_fails(env):
    ssm = FakeSSM({"/db/admin": '{"username": "admin", "password": "pw"}'})
    admin_db = FakeDB(("NOARCHIVELOG", "YES", "YES"))
    code, _ = run_main(env, ssm, admin_db)
    assert code == 1
    assert ssm.puts == [] and admin_db.statements() == []


def test_main_reports_a_password_that_differs_from_ssm(env, capsys):
    ssm = FakeSSM({
        "/db/admin": '{"username": "admin", "password": "pw"}',
        "/db/cdc-username": "cdc_user", "/db/cdc-password": "stale",
    })
    code, _ = run_main(env, ssm, FakeDB(user_exists=True),
                       login_error=oracledb.DatabaseError("ORA-01017: invalid username/password"))
    assert code == 1
    err = capsys.readouterr().err
    assert "cannot log in with the password in /db/cdc-password" in err
    assert "stale" not in err
