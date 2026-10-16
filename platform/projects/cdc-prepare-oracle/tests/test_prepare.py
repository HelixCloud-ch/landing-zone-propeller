"""First-pass unit tests for cdc-prepare-oracle/prepare.py.

Structural counterpart to cdc-prepare-mariadb/tests/test_prepare.py — same
fake-client shape, same helper names where the contract matches, adapted for
Oracle's differences: no bind variables in DDL (see prepare.py's module
docstring), a single-row V_$DATABASE precondition query instead of three
SHOW VARIABLES calls, and no ``IF NOT EXISTS``/``IF EXISTS`` forms on
``CREATE USER``.

oracledb and boto3 are imported lazily inside build_clients/build_ssm_client,
so read_inputs, read_admin_credential, verify_preconditions and
create_cdc_user are exercised here with a MagicMock ``ssm`` and a hand-rolled
fake db/cursor — no live database, no library installs required.
"""

from __future__ import annotations

import io
import os
import sys
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

import pytest

# prepare.py lives one directory up and is a top-level module (not a package),
# so make its directory importable regardless of where pytest is invoked from.
_PROJECT_DIR = Path(__file__).resolve().parent.parent
if str(_PROJECT_DIR) not in sys.path:
    sys.path.insert(0, str(_PROJECT_DIR))

import prepare  # noqa: E402  (path set up above)


# --------------------------------------------------------------------------- #
# Fakes — a minimal oracledb-shaped connection and cursor, offline.          #
#                                                                             #
# Unlike PyMySQL, Oracle DDL carries no bind variables at all (see prepare.py #
# module docstring) — every input-derived value is composed into the         #
# statement text itself (as a validated identifier or an escaped, quoted     #
# literal). FakeCursor therefore routes purely on statement TEXT, never on   #
# a params tuple.                                                            #
# --------------------------------------------------------------------------- #


class FakeCursor:
    """A minimal DB-API cursor recording every executed statement.

    ``responses`` maps a substring of the statement text to the row(s)
    ``fetchone``/``fetchall`` should return. The most recent execute
    determines what the fetch methods yield.
    """

    def __init__(self, responses: dict[str, object], executed: list[str]):
        self._responses = responses
        self._executed = executed
        self._last_rows: object = None
        self.closed = False

    def execute(self, statement):
        self._executed.append(statement)
        self._last_rows = None
        for needle, rows in self._responses.items():
            if needle in statement:
                self._last_rows = rows
                break

    def fetchone(self):
        rows = self._last_rows
        if not rows:
            return None
        return rows[0]

    def fetchall(self):
        return tuple(self._last_rows or ())

    def close(self):
        self.closed = True


class FakeDB:
    """A minimal oracledb-shaped connection over :class:`FakeCursor`.

    ``responses`` is keyed by a substring of the SQL/PLSQL statement text.
    ``executed`` collects every statement across all cursors so a test can
    assert what ran. ``commits`` counts ``commit()`` calls.
    """

    def __init__(self, responses=None):
        self._responses = responses or {}
        self.executed: list[str] = []
        self.commits = 0

    def cursor(self):
        return FakeCursor(self._responses, self.executed)

    def commit(self):
        self.commits += 1


# V_$DATABASE row shape: (LOG_MODE, SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK)
_GOOD_DATABASE_ROW = ("ARCHIVELOG", "YES", "YES")


def _database_responses(log_mode=None, supp_min=None, supp_pk=None):
    """Build a V_$DATABASE response map, overriding individual columns.

    An override of ``None`` keeps that column at its good value.
    """
    row = list(_GOOD_DATABASE_ROW)
    if log_mode is not None:
        row[0] = log_mode
    if supp_min is not None:
        row[1] = supp_min
    if supp_pk is not None:
        row[2] = supp_pk
    return {"FROM V_$DATABASE": [tuple(row)]}


def _base_inputs(**overrides) -> prepare.Inputs:
    fields = dict(
        db_host="oracle.example.internal",
        db_port=1521,
        service_name="ORCLCDB",
        pdb_name="ORCLPDB1",
        admin_credential_parameter="/cdc/admin",
        cdc_username="CDC_USER",
        cdc_username_parameter="/cdc/username",
        cdc_password_parameter="/cdc/password",
        archivelog_retention_hours=24,
        kms_key_id="alias/aws/ssm",
    )
    fields.update(overrides)
    return prepare.Inputs(**fields)


class FakeParameterNotFound(Exception):
    """Stand-in for the boto3 SSM ``exceptions.ParameterNotFound`` error."""


def _ssm_with_parameters(values: dict[str, str | None]) -> mock.MagicMock:
    """Build a mocked ssm client whose get_parameter routes by parameter Name.

    ``values`` maps a parameter name to its stored scalar value, or to ``None``
    to simulate that parameter being absent (get_parameter raises the mocked
    ``ParameterNotFound`` class, matching the real boto3 client's
    ``ssm.exceptions.ParameterNotFound`` contract used by
    ``_resolve_scalar_parameter``). A name not present in ``values`` is also
    treated as absent.

    The CDC credential now lives in TWO scalar parameters (username, password),
    each read with its own get_parameter call, so a per-Name router is required
    rather than a single return value.
    """
    ssm = mock.MagicMock()
    ssm.exceptions.ParameterNotFound = FakeParameterNotFound

    def _get_parameter(Name, WithDecryption=False):
        stored = values.get(Name)
        if stored is None:
            raise FakeParameterNotFound()
        return {"Parameter": {"Value": stored}}

    ssm.get_parameter.side_effect = _get_parameter
    return ssm


def _ssm_credential_params(
    username_value: str | None = None,
    password_value: str | None = None,
    *,
    username_param: str = "/cdc/username",
    password_param: str = "/cdc/password",
) -> mock.MagicMock:
    """Convenience wrapper over :func:`_ssm_with_parameters` for the CDC pair.

    Pass a stored scalar value for either parameter, or ``None`` (the default)
    to make it absent. Matches the default parameter names in
    :func:`_base_inputs`.
    """
    return _ssm_with_parameters(
        {username_param: username_value, password_param: password_value}
    )


# --------------------------------------------------------------------------- #
# 1. verify_preconditions — precondition logic                                #
# --------------------------------------------------------------------------- #


def test_preconditions_pass_when_all_good():
    db = FakeDB(responses=_database_responses())
    # Should not raise.
    prepare.verify_preconditions(db)


def test_preconditions_perform_no_modification():
    """verify_preconditions runs first and must not write anything.

    Asserts it issues only a SELECT and never commits — there is nothing to
    undo because it precedes every modification.
    """
    db = FakeDB(responses=_database_responses())
    prepare.verify_preconditions(db)

    assert db.commits == 0
    for statement in db.executed:
        assert statement.strip().upper().startswith("SELECT")


def test_precondition_not_archivelog_names_backup_retention():
    db = FakeDB(responses=_database_responses(log_mode="NOARCHIVELOG"))
    with pytest.raises(prepare.PreconditionError) as exc:
        prepare.verify_preconditions(db)
    msg = str(exc.value)
    assert "ARCHIVELOG" in msg
    assert "backup_retention_period" in msg
    assert db.commits == 0


def test_precondition_supplemental_min_not_enabled():
    db = FakeDB(responses=_database_responses(supp_min="NO"))
    with pytest.raises(prepare.PreconditionError) as exc:
        prepare.verify_preconditions(db)
    msg = str(exc.value)
    assert "SUPPLEMENTAL_LOG_DATA_MIN" in msg
    assert "alter_supplemental_logging" in msg


def test_precondition_supplemental_pk_not_enabled():
    db = FakeDB(responses=_database_responses(supp_pk="NO"))
    with pytest.raises(prepare.PreconditionError) as exc:
        prepare.verify_preconditions(db)
    msg = str(exc.value)
    assert "SUPPLEMENTAL_LOG_DATA_PK" in msg
    assert "PRIMARY KEY" in msg


def test_precondition_no_row_raises():
    """An empty V_$DATABASE result (e.g. missing SELECT privilege) is a clear
    precondition failure, not a silent pass or an unrelated exception."""
    db = FakeDB(responses={"FROM V_$DATABASE": []})
    with pytest.raises(prepare.PreconditionError) as exc:
        prepare.verify_preconditions(db)
    assert "V_$DATABASE" in str(exc.value)


# --------------------------------------------------------------------------- #
# 2. resolve_cdc_credential — parameter is the source of truth               #
# --------------------------------------------------------------------------- #


def _put_calls_for(ssm, param_name):
    """Return the list of put_parameter kwargs targeting ``param_name``."""
    return [
        call.kwargs
        for call in ssm.put_parameter.call_args_list
        if call.kwargs.get("Name") == param_name
    ]


def test_resolve_cdc_credential_creates_both_when_absent():
    """Both parameters absent -> username created from the input, password
    generated and created; each stored as a scalar SecureString value."""
    ssm = _ssm_credential_params(username_value=None, password_value=None)

    with mock.patch.object(
        prepare.secrets, "token_urlsafe", return_value="generated-password"
    ) as token:
        username, password = prepare.resolve_cdc_credential(
            ssm, "/cdc/username", "/cdc/password", "CDC_USER", "alias/aws/ssm"
        )

    assert token.call_count == 1
    assert username == "CDC_USER"
    assert password == "generated-password"

    user_puts = _put_calls_for(ssm, "/cdc/username")
    assert len(user_puts) == 1
    assert user_puts[0]["Type"] == "SecureString"
    assert user_puts[0]["KeyId"] == "alias/aws/ssm"
    assert user_puts[0]["Value"] == "CDC_USER"

    pw_puts = _put_calls_for(ssm, "/cdc/password")
    assert len(pw_puts) == 1
    assert pw_puts[0]["Type"] == "SecureString"
    assert pw_puts[0]["KeyId"] == "alias/aws/ssm"
    assert pw_puts[0]["Value"] == "generated-password"


def test_resolve_cdc_credential_reads_both_existing_unchanged():
    """Both parameters already exist -> read each scalar value, generate
    nothing, write nothing."""
    ssm = _ssm_credential_params(
        username_value="EXISTING_USER", password_value="kept-password"
    )

    with mock.patch.object(prepare.secrets, "token_urlsafe") as token:
        username, password = prepare.resolve_cdc_credential(
            ssm, "/cdc/username", "/cdc/password", "CDC_USER", "alias/aws/ssm"
        )

    token.assert_not_called()
    assert username == "EXISTING_USER"
    assert password == "kept-password"
    ssm.put_parameter.assert_not_called()


def test_resolve_cdc_credential_creates_only_the_missing_parameter():
    """Username parameter present, password parameter absent -> the existing
    username is read unchanged and only the password parameter is created."""
    ssm = _ssm_credential_params(
        username_value="EXISTING_USER", password_value=None
    )

    with mock.patch.object(
        prepare.secrets, "token_urlsafe", return_value="generated-password"
    ) as token:
        username, password = prepare.resolve_cdc_credential(
            ssm, "/cdc/username", "/cdc/password", "CDC_USER", "alias/aws/ssm"
        )

    assert token.call_count == 1
    assert username == "EXISTING_USER"
    assert password == "generated-password"

    assert _put_calls_for(ssm, "/cdc/username") == []
    pw_puts = _put_calls_for(ssm, "/cdc/password")
    assert len(pw_puts) == 1
    assert pw_puts[0]["Value"] == "generated-password"


# --------------------------------------------------------------------------- #
# 3. create_cdc_user — idempotency                                            #
# --------------------------------------------------------------------------- #


def test_create_cdc_user_first_run_creates_grants_and_retention():
    """First run: credential param absent AND db account absent -> CREATE
    USER, every system grant, every sys-object grant, and the retention CALL
    all run; credential param created."""
    db = FakeDB(responses={"FROM ALL_USERS": [(0,)]})
    ssm = _ssm_credential_params(username_value=None, password_value=None)
    inputs = _base_inputs()

    with mock.patch.object(
        prepare.secrets, "token_urlsafe", return_value="generated-password"
    ) as token:
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)

    statements = db.executed

    # CREATE USER runs on first creation, with the resolved password quoted.
    create = next(s for s in statements if s.startswith("CREATE USER"))
    assert prepare._quoted_literal("generated-password") in create
    assert token.call_count == 1

    # Every documented system grant runs, no fewer.
    granted = {s for s in statements if s.startswith("GRANT ")}
    for privilege in prepare.CDC_SYSTEM_GRANTS:
        assert any(s == f"GRANT {privilege} TO CDC_USER" for s in granted), privilege

    # Every sys-object grant runs via grant_sys_object.
    for obj_name, privilege in prepare.CDC_SYS_OBJECT_GRANTS:
        assert any(
            "grant_sys_object" in s and obj_name in s and privilege in s
            for s in statements
        ), (obj_name, privilege)

    # The retention procedure runs, with the hours composed as a literal.
    assert any(
        "set_configuration" in s and "'24'" in s for s in statements
    )

    # Both credential parameters were created as scalar SecureStrings.
    user_puts = _put_calls_for(ssm, inputs.cdc_username_parameter)
    assert len(user_puts) == 1
    assert user_puts[0]["Type"] == "SecureString"
    assert user_puts[0]["KeyId"] == inputs.kms_key_id
    assert user_puts[0]["Value"] == inputs.cdc_username

    pw_puts = _put_calls_for(ssm, inputs.cdc_password_parameter)
    assert len(pw_puts) == 1
    assert pw_puts[0]["Type"] == "SecureString"
    assert pw_puts[0]["KeyId"] == inputs.kms_key_id
    assert pw_puts[0]["Value"] == "generated-password"

    # The connection was committed at least once (every run_ddl call commits).
    assert db.commits > 0


def test_create_cdc_user_rerun_is_idempotent_and_does_not_touch_credential():
    """Re-run: credential param already exists AND db account already exists
    -> no CREATE USER, no password generated, credential param NOT written,
    no retention CALL — but grants still converge."""
    db = FakeDB(responses={"FROM ALL_USERS": [(1,)]})
    ssm = _ssm_credential_params(
        username_value="CDC_USER", password_value="existing-pw"
    )
    inputs = _base_inputs()

    with mock.patch.object(prepare.secrets, "token_urlsafe") as token:
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)

    statements = db.executed

    assert not any(s.startswith("CREATE USER") for s in statements)
    assert token.call_count == 0
    # Retention is set only on first creation — a re-run must not silently
    # override a value an operator may have since tuned.
    assert not any("set_configuration" in s for s in statements)

    # The credential parameter is NOT written — it is the source of truth.
    ssm.put_parameter.assert_not_called()
    # Grants still run to converge a partially-prepared account.
    assert any(s.startswith("GRANT ") for s in statements)
    assert any("grant_sys_object" in s for s in statements)


def test_create_cdc_user_creates_account_when_credential_param_pre_exists():
    """Consumer-supplied credential param already holds a value, but the DB
    account does not exist yet -> CREATE USER runs using that stored password,
    and the parameter is still never written."""
    db = FakeDB(responses={"FROM ALL_USERS": [(0,)]})
    ssm = _ssm_credential_params(
        username_value="CDC_USER", password_value="preexisting-pw"
    )
    inputs = _base_inputs()

    with mock.patch.object(prepare.secrets, "token_urlsafe") as token:
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)

    statements = db.executed
    create = next(s for s in statements if s.startswith("CREATE USER"))
    assert prepare._quoted_literal("preexisting-pw") in create
    token.assert_not_called()
    ssm.put_parameter.assert_not_called()


def test_create_cdc_user_rejects_unsafe_username():
    """A username outside the allowlist is refused before any statement runs."""
    db = FakeDB(responses={"FROM ALL_USERS": [(0,)]})
    ssm = _ssm_credential_params(username_value=None, password_value=None)
    inputs = _base_inputs(cdc_username="bad; DROP USER")

    with pytest.raises(prepare.InputError):
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)

    assert db.executed == []


def test_create_cdc_user_does_not_leak_password_to_output():
    """Light secrecy check (see test_prepare_properties.py for the thorough
    one): the generated password never appears on stdout or stderr."""
    db = FakeDB(responses={"FROM ALL_USERS": [(0,)]})
    ssm = _ssm_credential_params(username_value=None, password_value=None)
    inputs = _base_inputs()

    out, err = io.StringIO(), io.StringIO()
    with mock.patch.object(
        prepare.secrets, "token_urlsafe", return_value="super-secret-value"
    ):
        with redirect_stdout(out), redirect_stderr(err):
            prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)

    assert "super-secret-value" not in out.getvalue()
    assert "super-secret-value" not in err.getvalue()


# --------------------------------------------------------------------------- #
# 3. read_inputs — required-missing, defaults                                 #
# --------------------------------------------------------------------------- #


_REQUIRED_ENV = {
    "PROPELLER_INPUT_db_host": "oracle.example.internal",
    "PROPELLER_INPUT_service_name": "ORCLCDB",
    "PROPELLER_INPUT_admin_credential_parameter": "/cdc/admin",
    "PROPELLER_INPUT_cdc_username": "CDC_USER",
    "PROPELLER_INPUT_cdc_username_parameter": "/cdc/username",
    "PROPELLER_INPUT_cdc_password_parameter": "/cdc/password",
}


@pytest.fixture
def clean_env(monkeypatch):
    """Strip every PROPELLER_INPUT_* var so a test controls the full input set."""
    for key in list(os.environ):
        if key.startswith(prepare.INPUT_PREFIX):
            monkeypatch.delenv(key, raising=False)
    return monkeypatch


def test_read_inputs_missing_required_raises(clean_env):
    for key, value in _REQUIRED_ENV.items():
        if key != "PROPELLER_INPUT_db_host":
            clean_env.setenv(key, value)
    with pytest.raises(prepare.InputError) as exc:
        prepare.read_inputs()
    assert "db_host" in str(exc.value)


def test_read_inputs_applies_defaults(clean_env):
    for key, value in _REQUIRED_ENV.items():
        clean_env.setenv(key, value)
    # db_port, pdb_name, archivelog_retention_hours, kms_key_id all unset.
    inputs = prepare.read_inputs()
    assert inputs.db_port == prepare.DEFAULT_DB_PORT == 1521
    assert inputs.pdb_name == ""
    assert (
        inputs.archivelog_retention_hours
        == prepare.DEFAULT_ARCHIVELOG_RETENTION_HOURS
        == 24
    )
    assert inputs.kms_key_id == prepare.DEFAULT_KMS_KEY_ID == "alias/aws/ssm"


def test_read_inputs_reads_supplied_values(clean_env):
    for key, value in _REQUIRED_ENV.items():
        clean_env.setenv(key, value)
    clean_env.setenv("PROPELLER_INPUT_db_port", "1522")
    clean_env.setenv("PROPELLER_INPUT_pdb_name", "ORCLPDB1")
    clean_env.setenv("PROPELLER_INPUT_archivelog_retention_hours", "48")
    clean_env.setenv("PROPELLER_INPUT_kms_key_id", "alias/custom")
    inputs = prepare.read_inputs()
    assert inputs.db_port == 1522
    assert inputs.pdb_name == "ORCLPDB1"
    assert inputs.archivelog_retention_hours == 48
    assert inputs.kms_key_id == "alias/custom"


# --------------------------------------------------------------------------- #
# 4. read_admin_credential — JSON-doc and scalar forms                        #
# --------------------------------------------------------------------------- #


def _ssm_returning(value: str) -> mock.MagicMock:
    ssm = mock.MagicMock()
    ssm.get_parameter.return_value = {"Parameter": {"Value": value}}
    return ssm


def test_read_admin_credential_json_doc_form():
    ssm = _ssm_returning('{"username": "admin", "password": "s3cr3t"}')
    username, password = prepare.read_admin_credential(ssm, "/cdc/admin", "CDC_USER")
    assert username == "admin"
    assert password == "s3cr3t"
    ssm.get_parameter.assert_called_once_with(Name="/cdc/admin", WithDecryption=True)


def test_read_admin_credential_scalar_form_uses_fallback_username():
    ssm = _ssm_returning("just-a-password")
    username, password = prepare.read_admin_credential(ssm, "/cdc/admin", "CDC_USER")
    assert username == "CDC_USER"
    assert password == "just-a-password"


def test_read_admin_credential_json_missing_key_is_scalar():
    ssm = _ssm_returning('{"password": "only-password"}')
    username, password = prepare.read_admin_credential(ssm, "/cdc/admin", "CDC_USER")
    assert username == "CDC_USER"
    assert password == '{"password": "only-password"}'


# --------------------------------------------------------------------------- #
# 5. _quoted_literal — Oracle single-quote escaping                           #
# --------------------------------------------------------------------------- #


def test_quoted_literal_escapes_embedded_single_quotes():
    """Oracle's escaping rule: double every embedded single quote."""
    assert prepare._quoted_literal("simple") == "'simple'"
    assert prepare._quoted_literal("O'Brien") == "'O''Brien'"
    assert prepare._quoted_literal("a''b") == "'a''''b'"
    assert prepare._quoted_literal("") == "''"


def test_validated_identifier_rejects_sql_metacharacters():
    for bad in ("bad; DROP USER", "a'b", "1abc", "", "a" * 31, "a-b"):
        with pytest.raises(prepare.InputError):
            prepare._validated_identifier(bad, what="test")


def test_validated_identifier_accepts_oracle_identifier_grammar():
    for good in ("CDC_USER", "cdc_user", "A", "user_2#$", "X" * 30):
        assert prepare._validated_identifier(good, what="test") == good
