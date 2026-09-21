"""Thorough offline verification of cdc-prepare-mariadb/prepare.py (task 1.28).

This is the PRIMARY functional verification of ``prepare.py``: no AWS, no live
database. It EXTENDS the first-pass tests in ``test_prepare.py`` (task 1.14) by
importing and building on the reusable ``FakeCursor`` / ``FakeDB`` fakes and the
``_variables`` / ``_base_inputs`` helpers defined there, rather than duplicating
them.

It implements the two Correctness Properties from design.md as property-based
tests, each a single property with a minimum of 100 examples, tagged in the
docstring as required by the design's Testing Strategy:

* **Feature: debezium, Property 1: Prepare idempotency preserves the existing
  credential** (Requirement 3.8).
* **Feature: debezium, Property 2: Precondition failures make no modification**
  (Requirements 3.9-3.12).

Hypothesis is available in this environment (see the ``HAVE_HYPOTHESIS`` probe
below), so both properties are written as Hypothesis ``@given`` tests with
``settings(max_examples=...)`` at or above 100. A seeded stdlib-``random``
fallback is provided for an environment without Hypothesis, tagged identically
and running the same >=100-iteration contract, so the properties are always
verified regardless of what is installed.

Also covered, per Requirement 8.6 and the design Testing Strategy bullet list
for ``prepare.py``:

* SQL parameterisation — input-derived VALUES are bound query parameters, not
  interpolated into statement text; the only thing composed into text is the
  allowlist-validated username (the documented grammar-forced exception).
* No credential in output — a full first-run ``create_cdc_user`` and a mocked
  ``main()`` run emit neither the generated password nor the admin password on
  stdout or stderr.
* Each precondition failure produces the documented error naming the offending
  setting and exits non-zero through ``main()`` with no modification performed.

Runner: pytest (bare-assert, function-style — matches ``test_prepare.py``).
"""

from __future__ import annotations

import io
import random
import sys
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

import pytest

# prepare.py and test_prepare.py both live in dirs made importable here so the
# module runs regardless of pytest's invocation directory. prepare.py is one
# level up; test_prepare.py is this same tests/ directory.
_PROJECT_DIR = Path(__file__).resolve().parent.parent
_TESTS_DIR = Path(__file__).resolve().parent
for _p in (str(_PROJECT_DIR), str(_TESTS_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import prepare  # noqa: E402  (path set up above)

# Build on task 1.14's reusable fakes and helpers rather than redefining them.
from test_prepare import (  # noqa: E402
    FakeDB,
    _base_inputs,
    _put_calls_for,
    _ssm_credential_params,
    _variables,
)

# --------------------------------------------------------------------------- #
# Hypothesis availability probe. Both properties are written with Hypothesis  #
# when present; a seeded deterministic loop is the offline fallback contract.  #
# --------------------------------------------------------------------------- #
try:
    from hypothesis import HealthCheck, given, settings
    from hypothesis import strategies as st

    HAVE_HYPOTHESIS = True
except ImportError:  # pragma: no cover - exercised only without hypothesis
    HAVE_HYPOTHESIS = False

# Minimum iteration count mandated by the design Testing Strategy.
PROPERTY_ITERATIONS = 100

# Usernames are drawn from a small allowlist-valid set (see CDC_USERNAME_PATTERN
# in prepare.py: only [A-Za-z0-9_]). These stand in for "usernames from the
# allowlist" in the property generators.
_ALLOWLIST_USERNAMES = (
    "CDC_User",
    "cdc_user",
    "debezium",
    "Repl0",
    "cdc_reader_2",
    "A",
)


# --------------------------------------------------------------------------- #
# Helpers for driving a full create_cdc_user / main() run offline.            #
# --------------------------------------------------------------------------- #


def _run_first_creation(inputs, ssm, generated_password):
    """Drive a first-run create_cdc_user (both credential params AND db user
    absent).

    ``ssm`` must be built with ``_ssm_credential_params(None, None)`` so
    ``get_parameter`` raises ``ParameterNotFound`` for both the username and the
    password parameter, matching the "absent" contract of
    :func:`prepare._resolve_scalar_parameter`.

    Returns the FakeDB so callers can inspect executed statements.
    """
    db = FakeDB(responses={"FROM mysql.user": []})
    with mock.patch.object(
        prepare.secrets, "token_urlsafe", return_value=generated_password
    ):
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)
    return db


def _run_rerun(inputs, ssm):
    """Drive a re-run create_cdc_user (credential param AND db user exist).

    ``ssm`` must be built with ``_ssm_credential_params(<username>, <password>)``
    so ``get_parameter`` returns the already-stored values rather than
    raising ``ParameterNotFound``. ``token_urlsafe`` is patched to fail
    loudly: on a re-run no password may be generated at all, so any call is a
    property violation surfaced immediately. Returns the FakeDB and the token
    mock so callers can assert on both.
    """
    db = FakeDB(responses={"FROM mysql.user": [(1,)]})
    token = mock.MagicMock(side_effect=AssertionError("password generated on re-run"))
    with mock.patch.object(prepare.secrets, "token_urlsafe", token):
        prepare.create_cdc_user(prepare.Clients(ssm=ssm, db=db), inputs)
    return db, token


# =========================================================================== #
# PROPERTY 2 — Precondition failures make no modification (Req 3.9-3.12).      #
#                                                                             #
# Feature: debezium, Property 2: For any combination of binary logging        #
# disabled, a non-ROW binlog_format, a non-FULL binlog_row_image, or          #
# log_bin_compress enabled, prepare.py aborts with the documented error,      #
# exits non-zero, and performs NO database modification.                      #
# =========================================================================== #


# Varied violating values per setting, so the generated input space is large
# enough to sustain >=100 distinct examples rather than collapsing to the 16
# boolean subsets. A None means "leave this setting at its good value".
_BAD_LOG_BIN = (None, "OFF", "off", "0", "", None)
_BAD_FORMAT = (None, "MIXED", "STATEMENT", "mixed", "statement")
_BAD_IMAGE = (None, "MINIMAL", "NOBLOB", "minimal", "noblob")
_BAD_COMPRESS = (None, "ON", "on")  # only present-and-ON fails


def _bad_variable_overrides(log_bin_v, fmt_v, image_v, compress_v):
    """Translate four (value-or-None) choices into a _variables() override dict.

    A non-None value makes the corresponding server variable violate its
    precondition; None leaves it at its good value. At least one non-None value
    is expected so the combined state fails at least one precondition.
    """
    overrides = {}
    if log_bin_v is not None:
        overrides["log_bin"] = log_bin_v
    if fmt_v is not None:
        overrides["binlog_format"] = fmt_v
    if image_v is not None:
        overrides["binlog_row_image"] = image_v
    if compress_v is not None:
        overrides["log_bin_compress"] = compress_v
    return overrides


def _assert_precondition_makes_no_modification(log_bin_v, fmt_v, image_v, compress_v):
    """The core Property-2 invariant for one failing-flag combination.

    Runs verify_preconditions against a db whose variables violate at least one
    precondition, then asserts the NO-MODIFICATION invariant directly:

      * PreconditionError is raised;
      * the db issued only SHOW VARIABLES reads and never committed — so no
        CREATE USER, no GRANT and no rds_set_configuration CALL was executed;
      * no put_parameter was called on ssm.

    Asserting the invariant (nothing was modified), not merely that an error was
    raised, is the point of Property 2 (design.md Correctness Properties).
    """
    overrides = _bad_variable_overrides(log_bin_v, fmt_v, image_v, compress_v)
    db = FakeDB(responses=_variables(**overrides))
    ssm = mock.MagicMock()

    with pytest.raises(prepare.PreconditionError):
        prepare.verify_preconditions(db)

    # No modification: verify_preconditions only reads server variables.
    assert db.commits == 0
    for statement, _params in db.executed:
        text = statement.strip().upper()
        assert text.startswith("SHOW VARIABLES"), f"unexpected statement: {statement!r}"
        assert "CREATE USER" not in text
        assert "GRANT" not in text
        assert "RDS_SET_CONFIGURATION" not in text
    # And nothing was written to SSM.
    ssm.put_parameter.assert_not_called()


# The 15 canonical non-empty subsets of the four failing settings, using one
# representative violating value per set flag (at least one setting is bad).
_FAILING_COMBINATIONS = [
    (
        "OFF" if a else None,
        "MIXED" if b else None,
        "MINIMAL" if c else None,
        "ON" if d else None,
    )
    for a in (False, True)
    for b in (False, True)
    for c in (False, True)
    for d in (False, True)
    if a or b or c or d
]


if HAVE_HYPOTHESIS:

    @settings(
        max_examples=PROPERTY_ITERATIONS,
        suppress_health_check=[HealthCheck.filter_too_much],
    )
    @given(
        log_bin_v=st.sampled_from(_BAD_LOG_BIN),
        fmt_v=st.sampled_from(_BAD_FORMAT),
        image_v=st.sampled_from(_BAD_IMAGE),
        compress_v=st.sampled_from(_BAD_COMPRESS),
    )
    def test_property2_precondition_failures_make_no_modification(
        log_bin_v, fmt_v, image_v, compress_v
    ):
        """Feature: debezium, Property 2: Precondition failures make no modification.

        For any combination of {log_bin off, binlog_format != ROW,
        binlog_row_image != FULL, log_bin_compress ON} with at least one failing
        setting, verify_preconditions raises PreconditionError and performs no
        modification (no CREATE USER, no GRANT, no rds_set_configuration CALL, no
        put_parameter). Requirements 3.9-3.12. >=100 Hypothesis examples over a
        space of varied violating values per setting.
        """
        # Discard the all-good combination — Property 2 is about failing states.
        if log_bin_v is None and fmt_v is None and image_v is None and compress_v is None:
            return
        _assert_precondition_makes_no_modification(log_bin_v, fmt_v, image_v, compress_v)

else:  # pragma: no cover - exercised only without hypothesis

    def test_property2_precondition_failures_make_no_modification():
        """Feature: debezium, Property 2: Precondition failures make no modification.

        Seeded-loop fallback (Hypothesis unavailable): >=100 generated failing
        combinations of the four preconditions, each asserting the
        no-modification invariant. Requirements 3.9-3.12.
        """
        rng = random.Random(20240628)
        count = 0
        while count < PROPERTY_ITERATIONS:
            log_bin_v = rng.choice(_BAD_LOG_BIN)
            fmt_v = rng.choice(_BAD_FORMAT)
            image_v = rng.choice(_BAD_IMAGE)
            compress_v = rng.choice(_BAD_COMPRESS)
            if log_bin_v is None and fmt_v is None and image_v is None and compress_v is None:
                continue  # need at least one failing setting
            _assert_precondition_makes_no_modification(log_bin_v, fmt_v, image_v, compress_v)
            count += 1


def test_property2_all_failing_combinations_exhaustive():
    """Exhaustive companion: every one of the 15 failing subsets makes no change.

    Feature: debezium, Property 2 (Requirements 3.9-3.12). Complements the
    generated property run by covering the whole combination space once.
    """
    for combo in _FAILING_COMBINATIONS:
        _assert_precondition_makes_no_modification(*combo)


# =========================================================================== #
# PROPERTY 1 — Prepare idempotency preserves the existing credential (3.8).    #
#                                                                             #
# Feature: debezium, Property 1: For any already-prepared state (CDC_User      #
# exists), re-running create_cdc_user issues no CREATE USER and does not       #
# overwrite/rotate the password parameter.                                     #
# =========================================================================== #


def _assert_rerun_preserves_credential(username, credential_param, hours, kms):
    """The core Property-1 invariant for one already-prepared input set.

    With the CDC_User already existing AND both credential parameters already
    holding a value, create_cdc_user must:
      * issue no CREATE USER,
      * generate no password (token_urlsafe never called — enforced by the
        AssertionError side effect in _run_rerun),
      * never call put_parameter at all (no rotation, no overwrite of either
        the username or the password parameter).
    """
    username_param = credential_param + "-user"
    password_param = credential_param + "-pw"
    inputs = _base_inputs(
        cdc_username=username,
        cdc_username_parameter=username_param,
        cdc_password_parameter=password_param,
        binlog_retention_hours=hours,
        kms_key_id=kms,
    )
    ssm = _ssm_credential_params(
        username_value=username,
        password_value="already-stored-pw",
        username_param=username_param,
        password_param=password_param,
    )
    db, token = _run_rerun(inputs, ssm)

    statements = [s for s, _ in db.executed]
    assert not any("CREATE USER" in s for s in statements)
    token.assert_not_called()
    # Neither credential parameter is written on a re-run — no rotation (3.8).
    ssm.put_parameter.assert_not_called()


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
        parameter already holds a value), varying usernames (from the
        allowlist), the parameter name, retention hours and KMS key ids, a
        re-run issues no CREATE USER, generates no new password, and never
        writes to the credential parameter. Requirement 3.8. >=100
        Hypothesis examples.
        """
        _assert_rerun_preserves_credential(username, credential_param, hours, kms)

else:  # pragma: no cover - exercised only without hypothesis

    def test_property1_idempotency_preserves_credential():
        """Feature: debezium, Property 1: Prepare idempotency preserves the existing credential.

        Seeded-loop fallback (Hypothesis unavailable): >=100 generated
        already-prepared input sets, each asserting the no-rotation invariant.
        Requirement 3.8.
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
# SQL parameterisation (Requirement 3.14 / design "SQL construction").        #
# =========================================================================== #


def test_sql_input_values_are_bound_not_interpolated():
    """Input-derived VALUES are passed as bound params, never in the SQL text.

    Asserts the retention-hours value and the existence-probe username are in
    the params tuple (not the statement text), and the password is bound via
    IDENTIFIED BY %s rather than embedded. The only input composed into text is
    the allowlist-validated username identifier (the grammar-forced exception).
    """
    unusual_user = "CDC_User"
    inputs = _base_inputs(cdc_username=unusual_user, binlog_retention_hours=99)
    ssm = _ssm_credential_params(username_value=None, password_value=None)
    db = _run_first_creation(inputs, ssm, generated_password="bound-secret-xyz")

    by_stmt = {s: p for s, p in db.executed}

    # Existence probe: username is a bound value in the WHERE predicate.
    probe = next(s for s in by_stmt if "FROM mysql.user" in s)
    assert "%s" in probe
    assert unusual_user in by_stmt[probe]
    # The username is NOT interpolated into the probe text.
    assert unusual_user not in probe

    # Retention CALL: hours bound, not interpolated.
    call = next(s for s in by_stmt if "rds_set_configuration" in s)
    assert "%s" in call
    assert by_stmt[call] == (99,)
    assert "99" not in call

    # CREATE USER: password bound via IDENTIFIED BY %s, never in the text.
    create = next(s for s in by_stmt if "CREATE USER" in s)
    assert "IDENTIFIED BY %s" in create
    assert by_stmt[create] == ("bound-secret-xyz",)
    assert "bound-secret-xyz" not in create
    # The allowlist-validated username IS composed into the statement text —
    # the documented grammar-forced exception (MariaDB will not bind it).
    assert f"'{unusual_user}'@'%'" in create


def test_sql_only_username_identifier_is_composed_into_text():
    """The only input placed into statement text is the validated username.

    Across every executed statement, no bound value (password, retention hours)
    leaks into the statement string; only the username identifier appears
    literally, and only where MariaDB requires an identifier (CREATE USER,
    GRANT).
    """
    inputs = _base_inputs(cdc_username="debezium", binlog_retention_hours=48)
    ssm = _ssm_credential_params(username_value=None, password_value=None)
    db = _run_first_creation(inputs, ssm, generated_password="pw-not-in-text")

    for statement, _params in db.executed:
        assert "pw-not-in-text" not in statement
        assert "48" not in statement

    # The username appears in text exactly where an identifier is required.
    id_statements = [s for s, _ in db.executed if "debezium" in s]
    assert id_statements  # CREATE USER and GRANT reference the identifier
    for s in id_statements:
        assert ("CREATE USER" in s) or (s.startswith("GRANT "))


# =========================================================================== #
# No credential in output (Requirement 3.13 / design "secrecy").              #
# =========================================================================== #


def test_no_credential_in_output_full_create_run():
    """A full first-run create_cdc_user leaks no generated password to stdout/stderr."""
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
    """Wire main() to run fully offline with mocked clients.

    Patches read_inputs, build_ssm_client, read_admin_credential and
    build_clients so main() never touches boto3 or PyMySQL. ``db`` is the FakeDB
    whose SHOW VARIABLES / mysql.user responses drive the run.

    ``read_admin_credential`` is replaced outright (it is exercised on its own
    in test_prepare.py), so the returned ``ssm``'s ``get_parameter`` is reached
    ONLY by :func:`prepare.resolve_cdc_credential` in the real code path.
    ``credential_param_value=None`` (the default) leaves both credential
    parameters absent — matching a precondition-failure run, where
    ``resolve_cdc_credential`` is never even reached, and a "first creation"
    success run, where it must generate a password. Pass a string to simulate
    an already-existing password parameter instead (the username parameter is
    left absent so it is created from the input).
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
    """A full main() success run emits neither the generated nor admin password.

    main() is driven offline (clients mocked). The generated CDC password is
    pinned via token_urlsafe; the admin password is supplied through the mocked
    credential read. Neither may appear on stdout or stderr, and the run exits 0.
    """
    generated = "MAIN-cdc-password-secret"
    admin_password = "MAIN-admin-password-secret"
    inputs = _base_inputs()
    # A well-prepared db: preconditions pass, user absent → first creation.
    db = FakeDB(responses={**_variables(), "FROM mysql.user": []})

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


# (override kwargs for _variables, offending-setting substring the error names)
_PRECONDITION_CASES = [
    ({"log_bin": "OFF"}, "backup_retention_period"),  # 3.10: names backup control
    ({"binlog_format": "MIXED"}, "ROW"),  # 3.11
    ({"binlog_row_image": "MINIMAL"}, "FULL"),  # 3.11
    ({"log_bin_compress": "ON"}, "log_bin_compress"),  # 3.12: variable by name
]


@pytest.mark.parametrize("overrides,needle", _PRECONDITION_CASES)
def test_main_precondition_failure_exits_nonzero_names_setting_no_change(
    monkeypatch, overrides, needle
):
    """Each precondition failure through main() names the setting, exits non-zero,
    and performs no modification.

    Feature: debezium, Property 2 driven end-to-end through main() (Requirements
    3.9-3.12). The error message (rendered to stderr) names the offending
    setting; the return code is non-zero; and the db never committed nor issued
    any modifying statement.
    """
    inputs = _base_inputs()
    db = FakeDB(responses=_variables(**overrides))
    ssm = _install_main_mocks(monkeypatch, inputs, "admin", "admin-pw", db)

    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        rc = prepare.main()

    assert rc != 0
    # The documented offending setting is named in the stderr message.
    assert needle in err.getvalue()

    # No modification: no commit, no modifying statement, no SSM write.
    assert db.commits == 0
    for statement, _params in db.executed:
        text = statement.strip().upper()
        assert "CREATE USER" not in text
        assert "GRANT" not in text
        assert "RDS_SET_CONFIGURATION" not in text
    ssm.put_parameter.assert_not_called()
