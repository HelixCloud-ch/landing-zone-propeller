"""First-pass unit tests for cdc-prepare-mariadb/prepare.py (task 1.14).

These cover the precondition and idempotency logic (Requirement 8.5) without a
live database and without any library installs: boto3 and PyMySQL are imported
lazily inside build_clients/build_ssm_client, so read_inputs,
read_admin_credential, verify_preconditions and create_cdc_user are exercised
here with a MagicMock ``ssm`` and a hand-rolled fake db/cursor.

The more thorough offline verification (SQL parameterisation, no-credential-in-
output, every precondition path in full) is task 1.28; these tests are written
to be extended by that task rather than duplicated. Shared fakes live in module
scope (FakeCursor / FakeDB) so 1.28 can import and build on them.

Runner: pytest (bare-assert, function-style — matches engine/tests/). Falls
back to `python3 -m unittest` cleanly because every test is a plain function
with asserts and no pytest-only fixtures beyond monkeypatch, which is only used
for environment isolation.
"""

from __future__ import annotations

import io
import json
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
# Fakes — a minimal PyMySQL-shaped connection and cursor, offline.            #
# --------------------------------------------------------------------------- #


class FakeCursor:
    """A minimal DB-API cursor recording every executed statement.

    ``responses`` maps a substring to the row(s) that ``fetchone``/``fetchall``
    should return for the matching execute. Each needle is tested against both
    the statement text and the string form of the bound params, so a
    ``SHOW VARIABLES LIKE %s`` call is routed by its parameter (the variable
    name) rather than by the always-identical statement text. The most recent
    execute determines what the fetch methods yield.
    """

    def __init__(self, responses: dict[str, object], executed: list[tuple]):
        self._responses = responses
        self._executed = executed
        self._last_rows: object = None
        self.closed = False

    def execute(self, statement, params=()):
        self._executed.append((statement, params))
        self._last_rows = None
        haystack = statement + " " + " ".join(str(p) for p in params)
        for needle, rows in self._responses.items():
            if needle in haystack:
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
    """A minimal PyMySQL-shaped connection over :class:`FakeCursor`.

    ``responses`` is keyed by a substring of the SQL statement. ``executed``
    collects every (statement, params) pair across all cursors so a test can
    assert what ran. ``commits`` counts ``commit()`` calls. ``autocommit``
    controls what ``get_autocommit()`` returns; omit it entirely to simulate a
    driver that does not expose the method.
    """

    def __init__(self, responses=None, autocommit=False, expose_autocommit=True):
        self._responses = responses or {}
        self.executed: list[tuple] = []
        self.commits = 0
        self._autocommit = autocommit
        self._expose_autocommit = expose_autocommit

    def cursor(self):
        return FakeCursor(self._responses, self.executed)

    def commit(self):
        self.commits += 1

    def __getattr__(self, name):
        # Only expose get_autocommit when configured to; a missing attribute
        # raises AttributeError, matching a driver that autocommits by default.
        if name == "get_autocommit" and self._expose_autocommit:
            return lambda: self._autocommit
        raise AttributeError(name)


# Server-variable responses SHOW VARIABLES LIKE returns (Variable_name, Value).
_GOOD_VARIABLES = {
    "log_bin_compress": [("log_bin_compress", "OFF")],
    "log_bin": [("log_bin", "ON")],
    "binlog_format": [("binlog_format", "ROW")],
    "binlog_row_image": [("binlog_row_image", "FULL")],
}


def _variables(**overrides):
    """Build a SHOW VARIABLES response map, overriding individual variables.

    An override value of ``None`` drops the variable entirely (empty result set,
    i.e. the server does not expose it).
    """
    result = {k: list(v) for k, v in _GOOD_VARIABLES.items()}
    for name, value in overrides.items():
        if value is None:
            result[name] = []  # empty result set → variable absent
        else:
            result[name] = [(name, value)]
    return result


def _base_inputs(**overrides) -> prepare.Inputs:
    fields = dict(
        db_host="db.example.internal",
        db_port=3306,
        admin_credential_parameter="/cdc/admin",
        cdc_username="CDC_User",
        cdc_username_parameter="/cdc/username",
        cdc_password_parameter="/cdc/password",
        binlog_retention_hours=72,
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
    treated as absent, so a caller need only list the parameters that exist.

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
# 1. verify_preconditions — precondition logic (Requirement 3.9-3.12, 8.5)    #
# --------------------------------------------------------------------------- #


def test_preconditions_pass_when_all_four_good():
    db = FakeDB(responses=_variables())
    # Should not raise.
    prepare.verify_preconditions(db)


def test_preconditions_perform_no_modification():
    """verify_preconditions runs first and must not write anything.

    Assert it issues only SHOW VARIABLES reads and never commits — there is
    nothing to undo because it precedes every modification (Requirement 3.9).
    """
    db = FakeDB(responses=_variables())
    prepare.verify_preconditions(db)

    assert db.commits == 0
    for statement, _params in db.executed:
        assert statement.strip().upper().startswith("SHOW VARIABLES")


def test_precondition_log_bin_off_names_backup_retention():
    db = FakeDB(responses=_variables(log_bin="OFF"))
    with pytest.raises(prepare.PreconditionError) as exc:
        prepare.verify_preconditions(db)
    msg = str(exc.value)
    assert "log_bin" in msg
    # Names the RDS control that governs it (Requirement 3.10).
    assert "backup_retention_period" in msg
    assert db.commits == 0


def test_precondition_binlog_format_not_row():
    db = FakeDB(responses=_variables(binlog_format="MIXED"))
    with pytest.raises(prepare.PreconditionError) as exc:
        prepare.verify_preconditions(db)
    msg = str(exc.value)
    assert "binlog_format" in msg
    assert "ROW" in msg


def test_precondition_binlog_row_image_not_full():
    db = FakeDB(responses=_variables(binlog_row_image="MINIMAL"))
    with pytest.raises(prepare.PreconditionError) as exc:
        prepare.verify_preconditions(db)
    msg = str(exc.value)
    assert "binlog_row_image" in msg
    assert "FULL" in msg


def test_precondition_log_bin_compress_on():
    db = FakeDB(responses=_variables(log_bin_compress="ON"))
    with pytest.raises(prepare.PreconditionError) as exc:
        prepare.verify_preconditions(db)
    assert "log_bin_compress" in str(exc.value)


def test_precondition_log_bin_compress_absent_passes():
    """When the server does not expose log_bin_compress, absence is not-enabled."""
    db = FakeDB(responses=_variables(log_bin_compress=None))
    # Should not raise: an absent variable cannot compress the binary log.
    prepare.verify_preconditions(db)


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
            ssm, "/cdc/username", "/cdc/password", "CDC_User", "alias/aws/ssm"
        )

    # Exactly one password generated, for the absent password parameter.
    assert token.call_count == 1
    assert username == "CDC_User"
    assert password == "generated-password"

    # Username parameter: created as a scalar (the raw username, not JSON).
    user_puts = _put_calls_for(ssm, "/cdc/username")
    assert len(user_puts) == 1
    assert user_puts[0]["Type"] == "SecureString"
    assert user_puts[0]["KeyId"] == "alias/aws/ssm"
    assert user_puts[0]["Value"] == "CDC_User"

    # Password parameter: created as a scalar (the raw password, not JSON).
    pw_puts = _put_calls_for(ssm, "/cdc/password")
    assert len(pw_puts) == 1
    assert pw_puts[0]["Type"] == "SecureString"
    assert pw_puts[0]["KeyId"] == "alias/aws/ssm"
    assert pw_puts[0]["Value"] == "generated-password"


def test_resolve_cdc_credential_reads_both_existing_unchanged():
    """Both parameters already exist -> read each scalar value, generate
    nothing, write nothing."""
    ssm = _ssm_credential_params(
        username_value="existing_user", password_value="kept-password"
    )

    with mock.patch.object(prepare.secrets, "token_urlsafe") as token:
        username, password = prepare.resolve_cdc_credential(
            ssm, "/cdc/username", "/cdc/password", "CDC_User", "alias/aws/ssm"
        )

    token.assert_not_called()
    assert username == "existing_user"
    assert password == "kept-password"
    ssm.put_parameter.assert_not_called()


def test_resolve_cdc_credential_creates_only_the_missing_parameter():
    """Username parameter present, password parameter absent -> the existing
    username is read unchanged and only the password parameter is created."""
    ssm = _ssm_credential_params(
        username_value="existing_user", password_value=None
    )

    with mock.patch.object(
        prepare.secrets, "token_urlsafe", return_value="generated-password"
    ) as token:
        username, password = prepare.resolve_cdc_credential(
            ssm, "/cdc/username", "/cdc/password", "CDC_User", "alias/aws/ssm"
        )

    assert token.call_count == 1
    assert username == "existing_user"  # existing username wins over the input
    assert password == "generated-password"

    # The username parameter is never written (it already existed) ...
    assert _put_calls_for(ssm, "/cdc/username") == []
    # ... and only the password parameter is created.
    pw_puts = _put_calls_for(ssm, "/cdc/password")
    assert len(pw_puts) == 1
    assert pw_puts[0]["Value"] == "generated-password"


# --------------------------------------------------------------------------- #
# 3. create_cdc_user — idempotency (Requirement 3.5-3.8, 8.5)                 #
# --------------------------------------------------------------------------- #


def test_create_cdc_user_first_run_creates_grants_and_retention():
    """First run: both credential params absent AND db account absent -> CREATE
    USER, five-privilege GRANT, retention CALL all run; both credential params
    created as scalar SecureStrings."""
    # user-existence probe returns empty → first run.
    db = FakeDB(responses={"FROM mysql.user": []})
    ssm = _ssm_credential_params(username_value=None, password_value=None)
    inputs = _base_inputs()

    with mock.patch.object(
        prepare.secrets, "token_urlsafe", return_value="generated-password"
    ) as token:
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)

    statements = [s for s, _ in db.executed]

    # CREATE USER runs on first creation, with the resolved password bound.
    create = next(s for s in statements if "CREATE USER IF NOT EXISTS" in s)
    assert db.executed[statements.index(create)][1] == ("generated-password",)
    # A password was generated exactly once (by resolve_cdc_credential).
    assert token.call_count == 1

    # GRANT runs with exactly the five documented privileges, no more.
    grant = next(s for s in statements if s.startswith("GRANT "))
    for privilege in prepare.CDC_GRANTS:
        assert privilege in grant
    granted = grant[len("GRANT "):].split(" ON ", 1)[0]
    assert len([p.strip() for p in granted.split(",")]) == len(prepare.CDC_GRANTS)

    # The retention CALL runs with the hours bound as a parameter.
    call_stmt = next(
        (s, p) for s, p in db.executed if "rds_set_configuration" in s
    )
    assert call_stmt[1] == (inputs.binlog_retention_hours,)

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


def test_create_cdc_user_rerun_is_idempotent_and_does_not_touch_credential():
    """Re-run: both credential params already exist AND db account already
    exists -> no CREATE USER, no password generated, no credential param
    written."""
    # user-existence probe returns a row → user already exists.
    db = FakeDB(responses={"FROM mysql.user": [(1,)]})
    ssm = _ssm_credential_params(
        username_value="CDC_User", password_value="existing-pw"
    )
    inputs = _base_inputs()

    with mock.patch.object(prepare.secrets, "token_urlsafe") as token:
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)

    statements = [s for s, _ in db.executed]

    # No CREATE USER on a re-run.
    assert not any("CREATE USER" in s for s in statements)
    # No password generated — the parameter already existed.
    assert token.call_count == 0

    # Neither credential parameter is written — each is a source of truth.
    ssm.put_parameter.assert_not_called()
    # GRANT still runs to converge a partially-prepared account.
    assert any(s.startswith("GRANT ") for s in statements)


def test_create_cdc_user_creates_account_when_credential_param_pre_exists():
    """Consumer-supplied credential params already hold values, but the DB
    account does not exist yet -> CREATE USER runs using that stored password,
    and neither parameter is written."""
    db = FakeDB(responses={"FROM mysql.user": []})
    ssm = _ssm_credential_params(
        username_value="CDC_User", password_value="preexisting-pw"
    )
    inputs = _base_inputs()

    with mock.patch.object(prepare.secrets, "token_urlsafe") as token:
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)

    statements = [s for s, _ in db.executed]
    create = next(s for s in statements if "CREATE USER IF NOT EXISTS" in s)
    assert db.executed[statements.index(create)][1] == ("preexisting-pw",)
    token.assert_not_called()
    ssm.put_parameter.assert_not_called()


def test_create_cdc_user_rejects_unsafe_username():
    """A username outside the allowlist is refused before any statement runs.

    The unsafe username is created into the username parameter first (a scalar
    SecureString write is harmless — it never reaches a SQL statement), then
    the resolved username is rejected by the allowlist before any DDL runs.
    """
    db = FakeDB(responses={"FROM mysql.user": []})
    ssm = _ssm_credential_params(username_value=None, password_value=None)
    inputs = _base_inputs(cdc_username="bad; DROP USER")

    with pytest.raises(prepare.InputError):
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)

    # Nothing was executed against the database.
    assert db.executed == []


def test_create_cdc_user_does_not_leak_password_to_output():
    """The generated password never appears on stdout or stderr."""
    db = FakeDB(responses={"FROM mysql.user": []})
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
# 3. read_inputs — required-missing, defaults (Requirement 3.2-3.4, 3.17)     #
# --------------------------------------------------------------------------- #


_REQUIRED_ENV = {
    "PROPELLER_INPUT_db_host": "db.example.internal",
    "PROPELLER_INPUT_admin_credential_parameter": "/cdc/admin",
    "PROPELLER_INPUT_cdc_username": "CDC_User",
    "PROPELLER_INPUT_cdc_username_parameter": "/cdc/username",
    "PROPELLER_INPUT_cdc_password_parameter": "/cdc/password",
    "PROPELLER_INPUT_binlog_retention_hours": "72",
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
    # db_host is missing.
    with pytest.raises(prepare.InputError) as exc:
        prepare.read_inputs()
    assert "db_host" in str(exc.value)


def test_read_inputs_applies_defaults(clean_env):
    for key, value in _REQUIRED_ENV.items():
        clean_env.setenv(key, value)
    # db_port and kms_key_id intentionally unset → defaults apply.
    inputs = prepare.read_inputs()
    assert inputs.db_port == prepare.DEFAULT_DB_PORT == 3306
    assert inputs.kms_key_id == prepare.DEFAULT_KMS_KEY_ID == "alias/aws/ssm"


def test_read_inputs_reads_supplied_values(clean_env):
    for key, value in _REQUIRED_ENV.items():
        clean_env.setenv(key, value)
    clean_env.setenv("PROPELLER_INPUT_db_port", "3307")
    clean_env.setenv("PROPELLER_INPUT_kms_key_id", "alias/custom")
    inputs = prepare.read_inputs()
    assert inputs.db_port == 3307
    assert inputs.kms_key_id == "alias/custom"
    assert inputs.binlog_retention_hours == 72


# --------------------------------------------------------------------------- #
# 4. read_admin_credential — JSON-doc and scalar forms                        #
# --------------------------------------------------------------------------- #


def _ssm_returning(value: str) -> mock.MagicMock:
    ssm = mock.MagicMock()
    ssm.get_parameter.return_value = {"Parameter": {"Value": value}}
    return ssm


def test_read_admin_credential_json_doc_form():
    ssm = _ssm_returning('{"username": "admin", "password": "s3cr3t"}')
    username, password = prepare.read_admin_credential(ssm, "/cdc/admin", "CDC_User")
    assert username == "admin"
    assert password == "s3cr3t"
    # Read with decryption.
    ssm.get_parameter.assert_called_once_with(Name="/cdc/admin", WithDecryption=True)


def test_read_admin_credential_scalar_form_uses_fallback_username():
    ssm = _ssm_returning("just-a-password")
    username, password = prepare.read_admin_credential(ssm, "/cdc/admin", "CDC_User")
    assert username == "CDC_User"  # fallback used
    assert password == "just-a-password"


def test_read_admin_credential_json_missing_key_is_scalar():
    """A JSON value that is not an object with both keys is the scalar form."""
    ssm = _ssm_returning('{"password": "only-password"}')
    username, password = prepare.read_admin_credential(ssm, "/cdc/admin", "CDC_User")
    assert username == "CDC_User"
    assert password == '{"password": "only-password"}'
