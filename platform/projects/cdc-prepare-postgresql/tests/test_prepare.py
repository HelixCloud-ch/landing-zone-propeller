"""Tests for cdc-prepare-postgresql/prepare.py, with fake SSM and database clients.

Run: uv run --project platform/shared/python/cdc pytest platform/projects/cdc-prepare-postgresql
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import prepare  # noqa: E402

SECRET = "s3cr3t-admin-pw"


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    """Tests see only the inputs they set."""
    for key in list(os.environ):
        if key.startswith("PROPELLER_INPUT_") or key == "PGSSLROOTCERT":
            monkeypatch.delenv(key)


GOOD_SETTINGS = {
    "wal_level": "logical",
    "rds.logical_replication": "on",
    "max_replication_slots": "10",
    "max_wal_senders": "10",
    "max_slot_wal_keep_size": "10240",
    "log_statement": "none",
    "server_version_num": "160004",
}


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


def text_of(statement) -> str:
    return statement.as_string() if hasattr(statement, "as_string") else statement


class FakeCursor:
    def __init__(self, db):
        self.db = db
        self.rows: list[tuple] | None = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    @property
    def description(self):
        return None if self.rows is None else [("column",)]

    def execute(self, statement, params=None):
        db = self.db
        text = text_of(statement)
        db.executed.append((text, params))
        self.rows = None
        if "has_table_privilege" in text:
            schemas, _user = params
            self.rows = sorted(t for t in db.no_select if t[0] in schemas)
        elif "current_setting" in text:
            value = db.settings.get(params[0])
            self.rows = [(value,)]
        elif "FROM pg_replication_slots WHERE slot_name" in text:
            self.rows = [s[1:] for s in db.slots if s[0] == params[0]]
        elif text.startswith("SELECT count(*) FROM pg_replication_slots"):
            self.rows = [(len(db.slots),)]
        elif "pg_stat_replication" in text:
            self.rows = [(db.walsenders,)]
        elif "FROM pg_publication WHERE" in text:
            pub = db.publications.get(params[0])
            self.rows = [(pub["all"],)] if pub else []
        elif "FROM pg_publication_tables" in text:
            pub = db.publications[params[0]]
            self.rows = sorted(pub["tables"] if not pub["all"] else db.tables)
        elif "AS t(s, t)" in text:
            wanted = set(zip(*params))
            self.rows = sorted(wanted - db.tables)
        elif "FROM pg_class" in text:
            if "IN (SELECT * FROM unnest" in text:
                scope = set(zip(*params))
            else:
                scope = db.tables
            self.rows = sorted(db.keyless & scope)
        elif "FROM pg_roles" in text:
            self.rows = [(1,)] if params[0] in db.roles else []

    def fetchall(self):
        return self.rows


class FakeDB:
    def __init__(self, **overrides):
        self.settings = {**GOOD_SETTINGS, **overrides.pop("settings", {})}
        # (name, type, plugin, database, active, retained bytes)
        self.slots: list[tuple] = overrides.pop("slots", [])
        self.walsenders = overrides.pop("walsenders", 0)
        self.roles: set[str] = overrides.pop("roles", set())
        self.publications: dict[str, dict] = overrides.pop("publications", {})
        self.tables: set[tuple[str, str]] = overrides.pop("tables", {("public", "orders"), ("public", "items")})
        self.keyless: set[tuple[str, str]] = overrides.pop("keyless", set())
        # Tables on which the CDC role has no SELECT (a grant that did nothing).
        self.no_select: set[tuple[str, str]] = overrides.pop("no_select", set())
        assert not overrides, overrides
        self.executed: list[tuple] = []
        self.closed = False

    def cursor(self):
        return FakeCursor(self)

    def close(self):
        self.closed = True

    def statements(self) -> list[str]:
        """The statements that change the database."""
        return [
            text for text, _ in self.executed
            if text.startswith(("CREATE", "GRANT", "ALTER", "DROP"))
        ]


ENV = {
    "db_host": "db.example.internal",
    "db_name": "appdb",
    "admin_credential_parameter": "/db/admin",
    "cdc_username": "cdc_user",
    "cdc_username_parameter": "/db/cdc-username",
    "cdc_password_parameter": "/db/cdc-password",
}


@pytest.fixture
def env(monkeypatch):
    for key, value in ENV.items():
        monkeypatch.setenv(prepare.PREFIX + key, value)
    return monkeypatch


def set_input(monkeypatch, name, value):
    monkeypatch.setenv(prepare.PREFIX + name, value)


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
    assert inputs.db_port == 5432
    assert inputs.ssl_mode == "require"
    assert inputs.ssl_root_cert == ""
    assert inputs.schemas == ("public",)
    assert inputs.publication_name == "dbz_publication"
    assert inputs.publication_tables == ()
    assert inputs.manage_publication is True
    assert inputs.slot_name == "debezium"
    assert inputs.kms_key_id == "alias/aws/ssm"
    assert inputs.admin_username == ""


@pytest.mark.parametrize("name", [
    "db_host", "db_name", "admin_credential_parameter", "cdc_username",
    "cdc_username_parameter", "cdc_password_parameter",
])
def test_missing_required_input_exits_2(env, name, capsys):
    env.delenv(prepare.PREFIX + name)
    assert prepare.main() == 2
    assert prepare.PREFIX + name in capsys.readouterr().err


@pytest.mark.parametrize("name, value, message", [
    ("db_port", "abc", "must be an integer"),
    ("ssl_mode", "always", "must be one of"),
    ("manage_publication", "yes", "must be true or false"),
    ("schemas", "not json", "not valid JSON"),
    ("schemas", '{"a": 1}', "JSON list"),
    ("schemas", "[]", "at least one schema"),
    ("schemas", '["ok", "bad name"]', "must match"),
    ("publication_tables", "[1]", "JSON list"),
    ("publication_tables", '["orders"]', "schema.table"),
    ("publication_tables", '["public.or ders"]', "must match"),
    ("publication_tables", '["public.t\\"; DROP"]', "must match"),
    ("publication_name", "bad-name", "must match"),
    ("slot_name", "Upper", "must match"),
])
def test_bad_input_is_rejected(env, name, value, message):
    set_input(env, name, value)
    with pytest.raises(prepare.InputError, match=message):
        prepare.read_inputs()


def test_publication_tables_are_parsed(env):
    set_input(env, "schemas", '["public", "sales"]')
    set_input(env, "publication_tables", '["public.orders", "sales.items"]')
    assert prepare.read_inputs().publication_tables == (("public", "orders"), ("sales", "items"))


def test_publication_table_in_a_listed_schema_is_accepted(env):
    set_input(env, "publication_tables", '["public.orders"]')
    assert prepare.read_inputs().publication_tables == (("public", "orders"),)


def test_publication_table_in_an_unlisted_schema_is_an_input_error(env):
    set_input(env, "publication_tables", '["public.orders", "sales.items", "hr.staff"]')
    with pytest.raises(prepare.InputError, match=r"sales\.items, hr\.staff.*Add the schema to schemas"):
        prepare.read_inputs()


def test_main_exits_2_for_a_publication_table_in_an_unlisted_schema(env, capsys):
    set_input(env, "publication_tables", '["sales.items"]')
    assert prepare.main() == 2
    err = capsys.readouterr().err
    assert "sales.items" in err and "remove the entry" in err


def test_unmanaged_publication_with_tables_still_reports_the_manage_error(env):
    set_input(env, "manage_publication", "false")
    set_input(env, "publication_tables", '["sales.items"]')
    with pytest.raises(prepare.InputError, match="manage_publication=true"):
        prepare.read_inputs()


def test_empty_publication_tables_do_not_need_a_schema_check(env):
    set_input(env, "schemas", '["sales"]')
    set_input(env, "publication_tables", "[]")
    assert prepare.read_inputs().publication_tables == ()


def test_publication_tables_with_unmanaged_publication_is_an_error(env):
    set_input(env, "manage_publication", "false")
    set_input(env, "publication_tables", '["public.orders"]')
    with pytest.raises(prepare.InputError, match="manage_publication=true"):
        prepare.read_inputs()


@pytest.mark.parametrize("mode", prepare.SSL_MODES)
def test_every_ssl_mode_is_accepted(env, tmp_path, mode):
    ca = tmp_path / "ca.pem"
    ca.write_text("pem")
    set_input(env, "ssl_mode", mode)
    set_input(env, "ssl_root_cert", str(ca))
    inputs = prepare.read_inputs()
    assert inputs.ssl_mode == mode and inputs.ssl_root_cert == str(ca)


@pytest.mark.parametrize("mode", ["verify-ca", "verify-full"])
def test_verify_mode_needs_a_ca_bundle(env, mode):
    set_input(env, "ssl_mode", mode)
    with pytest.raises(prepare.InputError, match="PGSSLROOTCERT"):
        prepare.read_inputs()


@pytest.mark.parametrize("mode", ["verify-ca", "verify-full"])
def test_verify_mode_rejects_a_missing_ca_file(env, tmp_path, mode):
    set_input(env, "ssl_mode", mode)
    set_input(env, "ssl_root_cert", str(tmp_path / "absent.pem"))
    with pytest.raises(prepare.InputError, match="does not exist"):
        prepare.read_inputs()


def test_verify_mode_takes_the_ca_bundle_from_pgsslrootcert(env, tmp_path):
    ca = tmp_path / "ca.pem"
    ca.write_text("pem")
    set_input(env, "ssl_mode", "verify-full")
    env.setenv("PGSSLROOTCERT", str(ca))
    assert prepare.read_inputs().ssl_mode == "verify-full"
    env.setenv("PGSSLROOTCERT", str(tmp_path / "absent.pem"))
    with pytest.raises(prepare.InputError, match="does not exist"):
        prepare.read_inputs()


def test_connect_passes_ssl_options_to_the_driver(env, tmp_path, monkeypatch):
    ca = tmp_path / "ca.pem"
    ca.write_text("pem")
    set_input(env, "ssl_mode", "verify-full")
    set_input(env, "ssl_root_cert", str(ca))
    seen = {}
    monkeypatch.setattr(psycopg, "connect", lambda **kwargs: seen.update(kwargs))
    prepare.connect(prepare.read_inputs(), "u", "p")
    assert seen["sslmode"] == "verify-full" and seen["sslrootcert"] == str(ca)
    assert seen["dbname"] == "appdb" and seen["port"] == 5432


def test_connect_without_ca_bundle_sets_no_sslrootcert(env, monkeypatch):
    seen = {}
    monkeypatch.setattr(psycopg, "connect", lambda **kwargs: seen.update(kwargs))
    prepare.connect(prepare.read_inputs(), "u", "p")
    assert seen["sslmode"] == "require" and "sslrootcert" not in seen


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


def test_only_the_missing_parameter_is_created(env):
    ssm = FakeSSM({"/db/cdc-username": "other_user"})
    username, password = prepare.resolve_cdc_credential(ssm, prepare.read_inputs())
    assert username == "other_user" and password == ssm.params["/db/cdc-password"]
    assert [p["Name"] for p in ssm.puts] == ["/db/cdc-password"]


@pytest.mark.parametrize("username", ["x'; DROP ROLE a --", 'a"b', "1abc", "a b", "a" * 64])
def test_unsafe_username_is_rejected(env, username):
    ssm = FakeSSM({"/db/cdc-username": username, "/db/cdc-password": "p"})
    with pytest.raises(prepare.InputError, match="must match"):
        prepare.resolve_cdc_credential(ssm, prepare.read_inputs())


# ── Preconditions ────────────────────────────────────────────────────────────


def test_good_preconditions_pass(env, capsys):
    prepare.verify_preconditions(FakeDB(), prepare.read_inputs())
    out = capsys.readouterr()
    assert "wal_level=logical" in out.out and out.err == ""


def test_wal_level_not_logical_asks_for_the_parameter(env):
    db = FakeDB(settings={"wal_level": "replica", "rds.logical_replication": "off"})
    with pytest.raises(prepare.PrepareError, match=r"rds\.logical_replication=1.*parameter group.*reboot"):
        prepare.verify_preconditions(db, prepare.read_inputs())


def test_wal_level_not_logical_without_the_rds_setting_asks_for_the_parameter(env):
    db = FakeDB(settings={"wal_level": "replica", "rds.logical_replication": None})
    with pytest.raises(prepare.PrepareError, match=r"rds\.logical_replication=1"):
        prepare.verify_preconditions(db, prepare.read_inputs())


def test_wal_level_not_logical_with_the_parameter_on_asks_for_a_reboot(env):
    db = FakeDB(settings={"wal_level": "replica", "rds.logical_replication": "on"})
    with pytest.raises(prepare.PrepareError, match="reboot the DB instance"):
        prepare.verify_preconditions(db, prepare.read_inputs())


def full_slots(n, name="other"):
    return [(f"{name}{i}", "logical", "pgoutput", "appdb", True, 0) for i in range(n)]


def test_no_free_replication_slot_fails(env):
    db = FakeDB(settings={"max_replication_slots": "2"}, slots=full_slots(2))
    with pytest.raises(prepare.PrepareError, match="no free replication slot"):
        prepare.verify_preconditions(db, prepare.read_inputs())


def test_full_slots_are_fine_when_the_slot_already_exists(env):
    slots = full_slots(1) + [("debezium", "logical", "pgoutput", "appdb", True, 0)]
    prepare.verify_preconditions(
        FakeDB(settings={"max_replication_slots": "2"}, slots=slots), prepare.read_inputs()
    )


@pytest.mark.parametrize("slot", [
    ("debezium", "logical", "pgoutput", "otherdb", True, 0),
    ("debezium", "logical", "wal2json", "appdb", True, 0),
    ("debezium", "physical", None, None, False, None),
])
def test_foreign_slot_fails(env, slot):
    with pytest.raises(prepare.PrepareError, match="Debezium cannot use it"):
        prepare.verify_preconditions(FakeDB(slots=[slot]), prepare.read_inputs())


def test_slot_report_warns_about_an_inactive_slot_and_does_not_fail(env, capsys):
    slot = ("debezium", "logical", "pgoutput", "appdb", False, 123456)
    prepare.verify_preconditions(FakeDB(slots=[slot]), prepare.read_inputs())
    out = capsys.readouterr()
    assert "inactive, retained WAL 123456 bytes" in out.out
    assert "keeps 123456 bytes of WAL" in out.err


def test_slot_report_for_an_active_slot_has_no_warning(env, capsys):
    slot = ("debezium", "logical", "pgoutput", "appdb", True, 10)
    prepare.verify_preconditions(FakeDB(slots=[slot]), prepare.read_inputs())
    out = capsys.readouterr()
    assert "'debezium': active" in out.out and out.err == ""


def test_unbounded_wal_and_statement_logging_only_warn(env, capsys):
    db = FakeDB(settings={"max_slot_wal_keep_size": "-1", "log_statement": "ddl", "server_version_num": "90600"})
    prepare.verify_preconditions(db, prepare.read_inputs())
    err = capsys.readouterr().err
    assert "max_slot_wal_keep_size is -1" in err
    assert "log_statement" in err
    assert "older than 10" in err


# ── Publication ──────────────────────────────────────────────────────────────


def test_publication_for_all_tables_is_created(env):
    db = FakeDB()
    plan = prepare.plan_publication(db, prepare.read_inputs())
    assert plan.action == "create" and plan.tables == ()
    prepare.apply_publication(db, prepare.read_inputs(), plan)
    assert db.statements() == ['CREATE PUBLICATION "dbz_publication" FOR ALL TABLES']


def test_publication_for_a_table_list_is_created(env):
    set_input(env, "publication_tables", '["public.orders", "public.items"]')
    set_input(env, "publication_name", "my_pub")
    db = FakeDB()
    inputs = prepare.read_inputs()
    prepare.apply_publication(db, inputs, prepare.plan_publication(db, inputs))
    assert db.statements() == ['CREATE PUBLICATION "my_pub" FOR TABLE "public"."items", "public"."orders"']


def test_publication_that_is_already_correct_is_not_changed(env):
    db = FakeDB(publications={"dbz_publication": {"all": True, "tables": set()}})
    inputs = prepare.read_inputs()
    plan = prepare.plan_publication(db, inputs)
    prepare.apply_publication(db, inputs, plan)
    assert plan.action == "none" and db.statements() == []


def test_table_list_that_already_matches_is_not_changed(env):
    set_input(env, "publication_tables", '["public.orders"]')
    db = FakeDB(publications={"dbz_publication": {"all": False, "tables": {("public", "orders")}}})
    assert prepare.plan_publication(db, prepare.read_inputs()).action == "none"


def test_table_list_drift_is_synced(env):
    set_input(env, "publication_tables", '["public.orders", "public.items"]')
    db = FakeDB(publications={"dbz_publication": {"all": False, "tables": {("public", "orders")}}})
    inputs = prepare.read_inputs()
    plan = prepare.plan_publication(db, inputs)
    prepare.apply_publication(db, inputs, plan)
    assert plan.action == "alter"
    assert db.statements() == ['ALTER PUBLICATION "dbz_publication" SET TABLE "public"."items", "public"."orders"']


@pytest.mark.parametrize("all_tables, tables_input", [(True, '["public.orders"]'), (False, "[]")])
def test_publication_of_the_other_kind_is_refused_not_dropped(env, all_tables, tables_input):
    set_input(env, "publication_tables", tables_input)
    db = FakeDB(publications={"dbz_publication": {"all": all_tables, "tables": {("public", "orders")}}})
    with pytest.raises(prepare.PrepareError, match="cannot be switched"):
        prepare.plan_publication(db, prepare.read_inputs())
    assert db.statements() == []


def test_listed_table_that_does_not_exist_is_refused(env):
    set_input(env, "publication_tables", '["public.orders", "public.ghost"]')
    with pytest.raises(prepare.PrepareError, match="public.ghost"):
        prepare.plan_publication(FakeDB(), prepare.read_inputs())


def test_keyless_table_refuses_a_new_publication_and_names_it(env):
    db = FakeDB(keyless={("public", "items")})
    with pytest.raises(prepare.PrepareError, match=r"public\.items.*REPLICA IDENTITY FULL"):
        prepare.plan_publication(db, prepare.read_inputs())


def test_keyless_table_outside_the_list_does_not_refuse(env):
    set_input(env, "publication_tables", '["public.orders"]')
    db = FakeDB(keyless={("public", "items")})
    assert prepare.plan_publication(db, prepare.read_inputs()).action == "create"


def test_keyless_table_refuses_a_publication_change(env):
    set_input(env, "publication_tables", '["public.orders", "public.items"]')
    db = FakeDB(
        keyless={("public", "items")},
        publications={"dbz_publication": {"all": False, "tables": {("public", "orders")}}},
    )
    with pytest.raises(prepare.PrepareError, match=r"public\.items"):
        prepare.plan_publication(db, prepare.read_inputs())


def test_keyless_table_only_warns_when_the_publication_exists(env, capsys):
    db = FakeDB(
        keyless={("public", "items")},
        publications={"dbz_publication": {"all": True, "tables": set()}},
    )
    assert prepare.plan_publication(db, prepare.read_inputs()).action == "none"
    assert "public.items" in capsys.readouterr().err


@pytest.mark.parametrize("exists", [True, False])
def test_unmanaged_publication_is_only_reported(env, exists, capsys):
    set_input(env, "manage_publication", "false")
    pubs = {"dbz_publication": {"all": True, "tables": set()}} if exists else {}
    db = FakeDB(keyless={("public", "items")}, publications=pubs)
    inputs = prepare.read_inputs()
    plan = prepare.plan_publication(db, inputs)
    prepare.apply_publication(db, inputs, plan)
    assert plan.action == "none" and db.statements() == []
    out = capsys.readouterr()
    assert ("exists" if exists else "does not exist") in out.out
    assert out.err == ""
    assert not any("pg_class" in text for text, _ in db.executed)


# ── Role and grants ──────────────────────────────────────────────────────────


def test_prepare_user_creates_the_role_and_grants(env):
    db = FakeDB()
    set_input(env, "schemas", '["public", "sales"]')
    prepare.prepare_user(db, "cdc_user", "pw", prepare.read_inputs())
    assert db.statements() == [
        "CREATE ROLE \"cdc_user\" WITH LOGIN PASSWORD 'pw'",
        'GRANT rds_replication TO "cdc_user"',
        'GRANT USAGE ON SCHEMA "public" TO "cdc_user"',
        'GRANT SELECT ON ALL TABLES IN SCHEMA "public" TO "cdc_user"',
        'GRANT USAGE ON SCHEMA "sales" TO "cdc_user"',
        'GRANT SELECT ON ALL TABLES IN SCHEMA "sales" TO "cdc_user"',
    ]


def test_prepare_user_quotes_the_password(env):
    db = FakeDB()
    prepare.prepare_user(db, "cdc_user", "pw'; DROP ROLE x; --", prepare.read_inputs())
    create = db.statements()[0]
    assert create == "CREATE ROLE \"cdc_user\" WITH LOGIN PASSWORD 'pw''; DROP ROLE x; --'"


def test_prepare_user_is_idempotent_and_keeps_the_password(env):
    db = FakeDB(roles={"cdc_user"})
    prepare.prepare_user(db, "cdc_user", "new-password", prepare.read_inputs())
    statements = db.statements()
    assert not any(s.startswith(("CREATE ROLE", "ALTER ROLE")) for s in statements)
    assert statements[0] == 'GRANT rds_replication TO "cdc_user"'
    assert not any("new-password" in text for text, _ in db.executed)


# ── SELECT check ─────────────────────────────────────────────────────────────


def test_select_check_passes_when_all_privileges_are_present(env, capsys):
    set_input(env, "publication_tables", '["public.orders"]')
    db = FakeDB()
    prepare.verify_select_privilege(db, "cdc_user", prepare.read_inputs())
    assert capsys.readouterr().err == ""
    text, params = db.executed[-1]
    assert "has_table_privilege" in text and params == (["public"], "cdc_user")


def test_select_check_fails_for_a_listed_table_without_select(env):
    set_input(env, "publication_tables", '["public.orders", "public.items"]')
    db = FakeDB(no_select={("public", "orders")})
    with pytest.raises(prepare.PrepareError, match=r"public\.orders") as info:
        prepare.verify_select_privilege(db, "cdc_user", prepare.read_inputs())
    assert "public.items" not in str(info.value)


def test_select_check_only_warns_for_an_unlisted_table(env, capsys):
    set_input(env, "publication_tables", '["public.orders"]')
    db = FakeDB(no_select={("public", "items")})
    prepare.verify_select_privilege(db, "cdc_user", prepare.read_inputs())
    err = capsys.readouterr().err
    assert "no SELECT on 1 table(s)" in err and "public.items" in err


def test_select_check_only_warns_when_the_publication_is_not_managed(env, capsys):
    set_input(env, "manage_publication", "false")
    db = FakeDB(no_select={("public", "orders"), ("public", "items")})
    prepare.verify_select_privilege(db, "cdc_user", prepare.read_inputs())
    err = capsys.readouterr().err
    assert "no SELECT on 2 table(s)" in err
    assert "public.items, public.orders" in err


def test_select_check_only_warns_for_all_tables_publication(env, capsys):
    db = FakeDB(no_select={("public", "orders")})
    prepare.verify_select_privilege(db, "cdc_user", prepare.read_inputs())
    assert "public.orders" in capsys.readouterr().err


def test_select_check_caps_the_warning_list(env, capsys):
    tables = {("public", f"t{i:02d}") for i in range(25)}
    db = FakeDB(tables=tables, no_select=tables)
    prepare.verify_select_privilege(db, "cdc_user", prepare.read_inputs())
    err = capsys.readouterr().err
    assert "no SELECT on 25 table(s)" in err
    assert "t09" in err and "t10" not in err and "and 15 more" in err


def test_main_stops_before_the_publication_when_a_listed_table_has_no_select(env, capsys):
    set_input(env, "admin_username", "master")
    set_input(env, "publication_tables", '["public.orders"]')
    ssm = FakeSSM({"/db/admin": SECRET})
    admin_db = FakeDB(no_select={("public", "orders")})
    code, calls = run_main(env, ssm, admin_db)
    assert code == 1 and len(calls) == 1
    assert not any("PUBLICATION" in s for s in admin_db.statements())
    assert "public.orders" in capsys.readouterr().err


def test_main_finishes_with_a_warning_for_an_unlisted_table_without_select(env, capsys):
    set_input(env, "admin_username", "master")
    ssm = FakeSSM({"/db/admin": SECRET})
    admin_db = FakeDB(no_select={("public", "items")})
    code, _ = run_main(env, ssm, admin_db)
    assert code == 0
    assert 'CREATE PUBLICATION "dbz_publication" FOR ALL TABLES' in admin_db.statements()
    assert "public.items" in capsys.readouterr().err


# ── main ─────────────────────────────────────────────────────────────────────


def test_main_prepares_and_verifies_login(env, capsys):
    set_input(env, "admin_username", "master")
    ssm = FakeSSM({"/db/admin": SECRET})
    admin_db = FakeDB()
    code, calls = run_main(env, ssm, admin_db)
    assert code == 0
    assert calls[0] == ("master", SECRET)
    assert calls[1] == ("cdc_user", ssm.params["/db/cdc-password"])
    assert admin_db.closed
    assert admin_db.statements()[0].startswith('CREATE ROLE "cdc_user"')
    assert 'CREATE PUBLICATION "dbz_publication" FOR ALL TABLES' in admin_db.statements()
    out = capsys.readouterr()
    for secret in (SECRET, ssm.params["/db/cdc-password"]):
        assert secret not in out.out + out.err


def test_main_second_run_changes_nothing_new(env):
    set_input(env, "admin_username", "master")
    ssm = FakeSSM({"/db/admin": SECRET, "/db/cdc-username": "cdc_user", "/db/cdc-password": "kept"})
    admin_db = FakeDB(
        roles={"cdc_user"},
        publications={"dbz_publication": {"all": True, "tables": set()}},
    )
    code, calls = run_main(env, ssm, admin_db)
    assert code == 0 and ssm.puts == []
    assert not any(s.startswith(("CREATE", "ALTER", "DROP")) for s in admin_db.statements())
    assert calls[1] == ("cdc_user", "kept")


def test_main_changes_nothing_when_a_precondition_fails(env):
    set_input(env, "admin_username", "master")
    ssm = FakeSSM({"/db/admin": SECRET})
    admin_db = FakeDB(settings={"wal_level": "replica", "rds.logical_replication": "off"})
    code, calls = run_main(env, ssm, admin_db)
    assert code == 1
    assert ssm.puts == [] and admin_db.statements() == [] and len(calls) == 1
    assert admin_db.closed


def test_main_changes_nothing_when_the_replica_identity_check_fails(env, capsys):
    set_input(env, "admin_username", "master")
    ssm = FakeSSM({"/db/admin": SECRET})
    admin_db = FakeDB(keyless={("public", "items")})
    code, _ = run_main(env, ssm, admin_db)
    assert code == 1
    assert ssm.puts == [] and admin_db.statements() == []
    assert "public.items" in capsys.readouterr().err


def test_main_reports_a_password_that_differs_from_ssm(env, capsys):
    set_input(env, "admin_username", "master")
    ssm = FakeSSM({"/db/admin": SECRET, "/db/cdc-username": "cdc_user", "/db/cdc-password": "stale"})
    error = psycopg.OperationalError('password authentication failed for user "cdc_user"')
    code, _ = run_main(env, ssm, FakeDB(), login_error=error)
    assert code == 1
    err = capsys.readouterr().err
    assert "cannot log in with the password in /db/cdc-password" in err
    assert "stale" not in err


def test_main_reports_a_driver_error_without_traceback(env, monkeypatch, capsys):
    set_input(env, "admin_username", "master")

    def refuse(*_args):
        raise psycopg.OperationalError("connection failed\nline two")

    monkeypatch.setattr(prepare, "ssm_client", lambda: FakeSSM({"/db/admin": SECRET}))
    monkeypatch.setattr(prepare, "connect", refuse)
    assert prepare.main() == 1
    err = capsys.readouterr().err
    assert err == "cdc-prepare-postgresql: OperationalError: connection failed\n"


def test_main_reports_an_input_error_from_ssm_content(env, capsys):
    ssm = FakeSSM({"/db/admin": SECRET})
    code, _ = run_main(env, ssm, FakeDB())
    assert code == 2
    assert "admin_username" in capsys.readouterr().err


def test_main_with_bad_ssl_mode_exits_2(env, capsys):
    set_input(env, "ssl_mode", "always")
    assert prepare.main() == 2
    assert "ssl_mode" in capsys.readouterr().err
