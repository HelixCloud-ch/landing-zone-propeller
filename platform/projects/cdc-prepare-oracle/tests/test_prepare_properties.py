"""Thorough offline verification of cdc-prepare-oracle/prepare.py.

Structural counterpart to
cdc-prepare-mariadb/tests/test_prepare_properties.py — same two Correctness
Properties, same Hypothesis-with-seeded-fallback structure, adapted for
Oracle's single V_$DATABASE precondition query and no-bind-variables-in-DDL
statement composition.

No AWS, no live database. EXTENDS test_prepare.py by importing and building on
its FakeCursor/FakeDB and helper functions rather than duplicating them.

Implements:

* **Feature: debezium, Property 1: Prepare idempotency preserves the existing
  credential** — a re-run against an already-prepared database issues no
  CREATE USER, generates no password, and does not overwrite the password
  parameter.
* **Feature: debezium, Property 2: Precondition failures make no
  modification** — any combination of {not ARCHIVELOG, minimal supplemental
  logging disabled, primary-key supplemental logging disabled} aborts with
  PreconditionError and performs no modification.

Each property runs with Hypothesis (>=100 examples) when available, falling
back to a seeded stdlib-``random`` loop of the same iteration count otherwise —
the same dual-strategy contract as the MariaDB properties file.
"""

from __future__ import annotations

import io
import random
import sys
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

import pytest

_PROJECT_DIR = Path(__file__).resolve().parent.parent
_TESTS_DIR = Path(__file__).resolve().parent
for _p in (str(_PROJECT_DIR), str(_TESTS_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import prepare  # noqa: E402  (path set up above)

from test_prepare import (  # noqa: E402
    FakeDB,
    _base_inputs,
    _database_responses,
    _put_calls_for,
    _ssm_credential_params,
)

try:
    from hypothesis import HealthCheck, given, settings
    from hypothesis import strategies as st

    HAVE_HYPOTHESIS = True
except ImportError:  # pragma: no cover - exercised only without hypothesis
    HAVE_HYPOTHESIS = False

PROPERTY_ITERATIONS = 100

# Usernames drawn from Oracle's unquoted-identifier grammar (see
# CDC_USERNAME_PATTERN in prepare.py: [A-Za-z][A-Za-z0-9_#$]{0,29}).
_ALLOWLIST_USERNAMES = (
    "CDC_USER",
    "cdc_user",
    "DEBEZIUM",
    "Repl0",
    "cdc_reader_2",
    "A",
    "USER#1",
    "USER$X",
)


def _run_first_creation(inputs, ssm, generated_password):
    """Drive a first-run create_cdc_user (both credential params AND db user
    absent).

    ``ssm`` must be built with ``_ssm_credential_params(None, None)``.
    """
    db = FakeDB(responses={"FROM ALL_USERS": [(0,)]})
    with mock.patch.object(
        prepare.secrets, "token_urlsafe", return_value=generated_password
    ):
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)
    return db


def _run_rerun(inputs, ssm):
    """Drive a re-run create_cdc_user (both credential params AND db user
    exist).

    ``ssm`` must be built with ``_ssm_credential_params(<username>, <password>)``.
    ``token_urlsafe`` is patched to raise on any call: a re-run must generate
    no password at all, so any call is a property violation surfaced
    immediately rather than silently.
    """
    db = FakeDB(responses={"FROM ALL_USERS": [(1,)]})
    token = mock.MagicMock(side_effect=AssertionError("password generated on re-run"))
    with mock.patch.object(prepare.secrets, "token_urlsafe", token):
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)
    return db, token


# =========================================================================== #
# PROPERTY 2 — Precondition failures make no modification.                    #
#                                                                             #
# Feature: debezium, Property 2: For any combination of {database not in     #
# ARCHIVELOG mode, minimal supplemental logging disabled, primary-key         #
# supplemental logging disabled}, prepare.py aborts with the documented       #
# error, exits non-zero, and performs NO database modification.              #
# =========================================================================== #

_BAD_LOG_MODE = (None, "NOARCHIVELOG", "noarchivelog")
_BAD_SUPP_MIN = (None, "NO", "no")
_BAD_SUPP_PK = (None, "NO", "no")


def _bad_column_overrides(log_mode_v, supp_min_v, supp_pk_v):
    overrides = {}
    if log_mode_v is not None:
        overrides["log_mode"] = log_mode_v
    if supp_min_v is not None:
        overrides["supp_min"] = supp_min_v
    if supp_pk_v is not None:
        overrides["supp_pk"] = supp_pk_v
    return overrides


def _assert_precondition_makes_no_modification(log_mode_v, supp_min_v, supp_pk_v):
    """The core Property-2 invariant for one failing-column combination.

    Asserts the NO-MODIFICATION invariant directly: PreconditionError is
    raised; the db issued only a SELECT and never committed; no CREATE USER,
    GRANT, grant_sys_object or set_configuration statement ran; no
    put_parameter was called.
    """
    overrides = _bad_column_overrides(log_mode_v, supp_min_v, supp_pk_v)
    db = FakeDB(responses=_database_responses(**overrides))
    ssm = mock.MagicMock()

    with pytest.raises(prepare.PreconditionError):
        prepare.verify_preconditions(db)

    assert db.commits == 0
    for statement in db.executed:
        text = statement.strip().upper()
        assert text.startswith("SELECT"), f"unexpected statement: {statement!r}"
        assert "CREATE USER" not in text
        assert "GRANT" not in text
        assert "GRANT_SYS_OBJECT" not in text
        assert "SET_CONFIGURATION" not in text
    ssm.put_parameter.assert_not_called()


_FAILING_COMBINATIONS = [
    (
        "NOARCHIVELOG" if a else None,
        "NO" if b else None,
        "NO" if c else None,
    )
    for a in (False, True)
    for b in (False, True)
    for c in (False, True)
    if a or b or c
]


if HAVE_HYPOTHESIS:

    @settings(
        max_examples=PROPERTY_ITERATIONS,
        suppress_health_check=[HealthCheck.filter_too_much],
    )
    @given(
        log_mode_v=st.sampled_from(_BAD_LOG_MODE),
        supp_min_v=st.sampled_from(_BAD_SUPP_MIN),
        supp_pk_v=st.sampled_from(_BAD_SUPP_PK),
    )
    def test_property2_precondition_failures_make_no_modification(
        log_mode_v, supp_min_v, supp_pk_v
    ):
        """Feature: debezium, Property 2: Precondition failures make no modification.

        For any combination of {LOG_MODE != ARCHIVELOG,
        SUPPLEMENTAL_LOG_DATA_MIN != YES, SUPPLEMENTAL_LOG_DATA_PK != YES} with
        at least one failing column, verify_preconditions raises
        PreconditionError and performs no modification. >=100 Hypothesis
        examples.
        """
        if log_mode_v is None and supp_min_v is None and supp_pk_v is None:
            return  # Property 2 is about failing states, not the all-good one.
        _assert_precondition_makes_no_modification(log_mode_v, supp_min_v, supp_pk_v)

else:  # pragma: no cover - exercised only without hypothesis

    def test_property2_precondition_failures_make_no_modification():
        """Feature: debezium, Property 2: Precondition failures make no modification.

        Seeded-loop fallback (Hypothesis unavailable): >=100 generated failing
        combinations of the three preconditions.
        """
        rng = random.Random(20240628)
        count = 0
        while count < PROPERTY_ITERATIONS:
            log_mode_v = rng.choice(_BAD_LOG_MODE)
            supp_min_v = rng.choice(_BAD_SUPP_MIN)
            supp_pk_v = rng.choice(_BAD_SUPP_PK)
            if log_mode_v is None and supp_min_v is None and supp_pk_v is None:
                continue
            _assert_precondition_makes_no_modification(log_mode_v, supp_min_v, supp_pk_v)
            count += 1


def test_property2_all_failing_combinations_exhaustive():
    """Exhaustive companion: every one of the 7 failing subsets makes no change.

    Feature: debezium, Property 2. Complements the generated property run by
    covering the whole combination space once.
    """
    for combo in _FAILING_COMBINATIONS:
        _assert_precondition_makes_no_modification(*combo)


# =========================================================================== #
# PROPERTY 1 — Prepare idempotency preserves the existing credential.         #
#                                                                             #
# Feature: debezium, Property 1: For any already-prepared state (CDC user     #
# exists), re-running create_cdc_user issues no CREATE USER, generates no     #
# password, and does not overwrite/rotate the password parameter.             #
# =========================================================================== #


def _assert_rerun_preserves_credential(username, credential_param, hours, kms):
    username_param = credential_param + "-user"
    password_param = credential_param + "-pw"
    inputs = _base_inputs(
        cdc_username=username,
        cdc_username_parameter=username_param,
        cdc_password_parameter=password_param,
        archivelog_retention_hours=hours,
        kms_key_id=kms,
    )
    ssm = _ssm_credential_params(
        username_value=username,
        password_value="already-stored-pw",
        username_param=username_param,
        password_param=password_param,
    )
    db, token = _run_rerun(inputs, ssm)

    assert not any(s.startswith("CREATE USER") for s in db.executed)
    token.assert_not_called()
    # Neither credential parameter is written on a re-run — no rotation.
    ssm.put_parameter.assert_not_called()
    # Retention is set only on first creation; a re-run must not silently
    # override a value an operator may have since tuned.
    assert not any("SET_CONFIGURATION" in s.upper() for s in db.executed)


if HAVE_HYPOTHESIS:

    _param_names = st.text(
        alphabet="abcdefghijklmnopqrstuvwxyz/_-0123456789",
        min_size=1,
        max_size=40,
    ).map(lambda s: "/" + s)

    @settings(max_examples=PROPERTY_ITERATIONS)
    @given(
        username=st.sampled_from(_ALLOWLIST_USERNAMES),
        credential_param=_param_names,
        hours=st.integers(min_value=1, max_value=168),
        kms=st.sampled_from(
            ["alias/aws/ssm", "alias/custom", "arn:aws:kms:eu-west-1:111122223333:key/abc"]
        ),
    )
    def test_property1_idempotency_preserves_credential(
        username, credential_param, hours, kms
    ):
        """Feature: debezium, Property 1: Prepare idempotency preserves the existing credential.

        For any already-prepared state (user exists AND the credential
        parameter already holds a value), varying usernames (from Oracle's
        identifier allowlist), the parameter name, retention hours and KMS
        key ids, a re-run issues no CREATE USER, generates no new password,
        and never writes to the credential parameter. >=100 Hypothesis
        examples.
        """
        _assert_rerun_preserves_credential(username, credential_param, hours, kms)

else:  # pragma: no cover - exercised only without hypothesis

    def test_property1_idempotency_preserves_credential():
        """Feature: debezium, Property 1: Prepare idempotency preserves the existing credential.

        Seeded-loop fallback (Hypothesis unavailable): >=100 generated
        already-prepared input sets, each asserting the no-rotation
        invariant.
        """
        rng = random.Random(20240628)
        kms_choices = [
            "alias/aws/ssm",
            "alias/custom",
            "arn:aws:kms:eu-west-1:111122223333:key/abc",
        ]
        alphabet = "abcdefghijklmnopqrstuvwxyz/_-0123456789"
        for _ in range(PROPERTY_ITERATIONS):
            username = rng.choice(_ALLOWLIST_USERNAMES)
            cparam = "/" + "".join(
                rng.choice(alphabet) for _ in range(rng.randint(1, 40))
            )
            hours = rng.randint(1, 168)
            kms = rng.choice(kms_choices)
            _assert_rerun_preserves_credential(username, cparam, hours, kms)


# =========================================================================== #
# No bind variables anywhere — every composed value is validated or quoted.   #
# =========================================================================== #


def test_no_statement_ever_carries_a_bind_placeholder():
    """Oracle DDL cannot bind ANY variable (see prepare.py module docstring).

    Every statement this module issues must therefore be immediately
    executable text with no driver-level placeholder of any kind — assert
    none of the common placeholder spellings (:1, %s, ?) ever appear.
    """
    inputs = _base_inputs()
    ssm = _ssm_credential_params(username_value=None, password_value=None)
    db = _run_first_creation(inputs, ssm, generated_password="no-bind-vars-here")

    for statement in db.executed:
        assert "%s" not in statement
        assert "?" not in statement
        assert not any(f":{n}" in statement for n in range(1, 10))


def test_password_is_escaped_and_quoted_never_raw_in_create_user():
    """A password containing a single quote is safely escaped, not raw text.

    Regression guard for the one place a genuine secret value (not an
    identifier) is composed into Oracle DDL text.
    """
    inputs = _base_inputs()
    ssm = _ssm_credential_params(username_value=None, password_value=None)
    tricky_password = "abc'; DROP TABLE x; --"

    db = _run_first_creation(inputs, ssm, generated_password=tricky_password)

    create = next(s for s in db.executed if s.startswith("CREATE USER"))
    # The raw password (with an unescaped quote) must never appear verbatim;
    # only the escaped form (every ' doubled) may.
    escaped = prepare._quoted_literal(tricky_password)
    assert escaped in create
    assert tricky_password not in create  # the raw (unescaped) form is absent


# =========================================================================== #
# No credential in output.                                                     #
# =========================================================================== #


def test_no_credential_in_output_full_create_run():
    secret = "PROP-generated-password-DO-NOT-LEAK"
    inputs = _base_inputs()
    ssm = _ssm_credential_params(username_value=None, password_value=None)

    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        _run_first_creation(inputs, ssm, generated_password=secret)

    assert secret not in out.getvalue()
    assert secret not in err.getvalue()


def _install_main_mocks(
    monkeypatch, inputs, admin_username, admin_password, db, *, credential_param_value=None
):
    """``read_admin_credential`` is replaced outright, so the returned ssm's
    ``get_parameter`` is reached ONLY by :func:`prepare.resolve_cdc_credential`
    in the real code path. ``credential_param_value=None`` leaves both
    credential parameters absent; pass a string to simulate an existing
    password parameter (the username parameter is left absent).
    """
    ssm = _ssm_credential_params(
        username_value=None,
        password_value=credential_param_value,
        username_param=inputs.cdc_username_parameter,
        password_param=inputs.cdc_password_parameter,
    )
    monkeypatch.setattr(prepare, "read_inputs", lambda: inputs)
    monkeypatch.setattr(prepare, "build_ssm_client", lambda: ssm)
    monkeypatch.setattr(
        prepare,
        "read_admin_credential",
        lambda _ssm, _param, _fallback: (admin_username, admin_password),
    )
    monkeypatch.setattr(
        prepare, "build_clients", lambda _inputs, _u, _p: prepare.Clients(ssm=ssm, db=db)
    )
    return ssm


def test_main_success_run_leaks_no_credential(monkeypatch):
    generated = "MAIN-cdc-password-secret"
    admin_password = "MAIN-admin-password-secret"
    inputs = _base_inputs()
    db = FakeDB(responses={**_database_responses(), "FROM ALL_USERS": [(0,)]})

    _install_main_mocks(monkeypatch, inputs, "admin", admin_password, db)

    out, err = io.StringIO(), io.StringIO()
    with mock.patch.object(prepare.secrets, "token_urlsafe", return_value=generated):
        with redirect_stdout(out), redirect_stderr(err):
            rc = prepare.main()

    assert rc == 0
    combined = out.getvalue() + err.getvalue()
    assert generated not in combined
    assert admin_password not in combined


# =========================================================================== #
# Documented precondition errors through main() — non-zero exit, no change.   #
# =========================================================================== #


_PRECONDITION_CASES = [
    ({"log_mode": "NOARCHIVELOG"}, "backup_retention_period"),
    ({"supp_min": "NO"}, "SUPPLEMENTAL_LOG_DATA_MIN"),
    ({"supp_pk": "NO"}, "SUPPLEMENTAL_LOG_DATA_PK"),
]


@pytest.mark.parametrize("overrides,needle", _PRECONDITION_CASES)
def test_main_precondition_failure_exits_nonzero_names_setting_no_change(
    monkeypatch, overrides, needle
):
    """Each precondition failure through main() names the setting, exits
    non-zero, and performs no modification."""
    inputs = _base_inputs()
    db = FakeDB(responses=_database_responses(**overrides))
    ssm = _install_main_mocks(monkeypatch, inputs, "admin", "admin-pw", db)

    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        rc = prepare.main()

    assert rc != 0
    assert needle in err.getvalue()

    assert db.commits == 0
    for statement in db.executed:
        text = statement.strip().upper()
        assert "CREATE USER" not in text
        assert "GRANT" not in text
    ssm.put_parameter.assert_not_called()
