"""Integration tests: the CDC scripts against real MariaDB, Oracle and Kafka.

The services come from compose.yaml (`just cdc-up`). SSM is faked. Each test
uses new names, so the tests also pass against services that are already in
use.

Run: just test-cdc-integration
 or: just cdc-up, then
     uv run --project platform/shared/python/cdc pytest platform/shared/python/cdc/tests
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import uuid
from pathlib import Path

import oracledb
import pymysql
import pytest
from kafka.admin import KafkaAdminClient

PROJECTS = Path(__file__).resolve().parents[5] / "platform" / "projects"


def load(project: str, module: str):
    """Import a project's script under a unique name (two are called prepare)."""
    name = f"{project.replace('-', '_')}_{module}"
    spec = importlib.util.spec_from_file_location(name, PROJECTS / project / f"{module}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod  # dataclasses look the module up while it loads
    spec.loader.exec_module(mod)
    return mod


class FakeSSM:
    class exceptions:
        class ParameterNotFound(Exception):
            pass

    def __init__(self, params: dict[str, str]):
        self.params = dict(params)

    def get_parameter(self, Name, WithDecryption):
        if Name not in self.params:
            raise self.exceptions.ParameterNotFound(Name)
        return {"Parameter": {"Value": self.params[Name]}}

    def put_parameter(self, Name, Value, **_):
        self.params[Name] = Value


@pytest.fixture
def run(monkeypatch, capsys):
    """run(module, inputs, ssm=None) -> (exit code, output)."""

    def _run(module, inputs: dict[str, str], ssm=None):
        for key in list(os.environ):
            if key.startswith("PROPELLER_INPUT_"):
                monkeypatch.delenv(key)
        for key, value in inputs.items():
            monkeypatch.setenv("PROPELLER_INPUT_" + key, value)
        if ssm is not None:
            monkeypatch.setattr(module, "ssm_client", lambda: ssm)
        code = module.main()
        out = capsys.readouterr()
        return code, out.out + out.err

    return _run


def cdc_inputs(user: str) -> dict[str, str]:
    return {
        "admin_credential_parameter": "/admin",
        "cdc_username": user,
        "cdc_username_parameter": "/cdc/username",
        "cdc_password_parameter": "/cdc/password",
    }


# ── MariaDB ──────────────────────────────────────────────────────────────────


def test_mariadb(run):
    prepare = load("cdc-prepare-mariadb", "prepare")
    user = "cdc_" + uuid.uuid4().hex[:8]
    ssm = FakeSSM({"/admin": "rootpw"})
    inputs = {**cdc_inputs(user), "db_host": "127.0.0.1", "db_port": "33306",
              "admin_username": "root", "binlog_retention_hours": "168"}

    code, out = run(prepare, inputs, ssm)
    assert code == 0, out

    root = pymysql.connect(host="127.0.0.1", port=33306, user="root", password="rootpw")
    with root.cursor() as cur:
        cur.execute(f"SHOW GRANTS FOR '{user}'@'%'")
        grants = cur.fetchone()[0]
    root.close()
    assert "REPLICATION SLAVE" in grants and "SHOW DATABASES" in grants

    # A password that differs from the database fails the login check.
    ssm.params["/cdc/password"] = "not-the-password"
    code, out = run(prepare, inputs, ssm)
    assert code == 1 and "cannot log in with the password in /cdc/password" in out
    assert "not-the-password" not in out


# ── Oracle ───────────────────────────────────────────────────────────────────


def test_oracle(run):
    prepare = load("cdc-prepare-oracle", "prepare")
    user = "CDC_" + uuid.uuid4().hex[:8].upper()
    ssm = FakeSSM({"/admin": json.dumps({"username": "admin", "password": "adminpw"})})
    inputs = {**cdc_inputs(user), "db_host": "127.0.0.1", "db_port": "31521",
              "service_name": "FREE", "pdb_name": "FREEPDB1",
              "archivelog_retention_hours": "24"}

    code, out = run(prepare, inputs, ssm)
    assert code == 0, out

    admin = oracledb.connect(host="127.0.0.1", port=31521, service_name="FREEPDB1",
                             user="admin", password="adminpw")
    with admin.cursor() as cur:
        cur.execute("SELECT privilege FROM dba_sys_privs WHERE grantee = :u", {"u": user})
        sys_privs = {row[0] for row in cur}
        cur.execute("SELECT table_name FROM dba_tab_privs WHERE grantee = :u", {"u": user})
        objects = {row[0] for row in cur}
    admin.close()
    assert {"CREATE SESSION", "LOGMINING", "SELECT ANY TRANSACTION"} <= sys_privs
    assert {"DBMS_LOGMNR", "V_$DATABASE", "V_$LOGMNR_CONTENTS"} <= objects

    ssm.params["/cdc/password"] = "not-the-password"
    code, out = run(prepare, inputs, ssm)
    assert code == 1 and "cannot log in with the password in /cdc/password" in out
    assert "not-the-password" not in out


# ── Kafka ────────────────────────────────────────────────────────────────────


def test_kafka(run):
    topics = load("cdc-topics", "topics")
    suffix = uuid.uuid4().hex[:8]
    requested = [
        {"name": f"schema-history.{suffix}", "partitions": 1,
         "configs": {"cleanup.policy": "delete", "retention.ms": "-1", "retention.bytes": "-1"}},
        {"name": f"connect-offsets.{suffix}", "partitions": 3,
         "configs": {"cleanup.policy": "compact"}},
    ]
    code, out = run(topics, {"bootstrap_servers": "localhost:9092",
                             "security_protocol": "PLAINTEXT",
                             "topics": json.dumps(requested)})
    assert code == 0, out

    admin = KafkaAdminClient(bootstrap_servers=["localhost:9092"])
    try:
        assert {t["name"] for t in requested} <= set(admin.list_topics())
    finally:
        admin.close()


def test_kafka_unreachable_cluster_fails(run):
    topics = load("cdc-topics", "topics")
    code, out = run(topics, {"bootstrap_servers": "localhost:1", "security_protocol": "PLAINTEXT"})
    assert code == 1 and "Kafka error on localhost:1" in out
