"""Offline unit tests for cdc-topics/topics.py (task 1.29, Requirement 8.6).

topics.py imports ``from kafka.admin import KafkaAdminClient, NewTopic`` and
``from kafka.errors import KafkaError, TopicAlreadyExistsError`` at module top
level, and ``aws_msk_iam_sasl_signer`` lazily inside build_token_provider.
kafka-python is baked into the deploy-runner image but is NOT necessarily
installed in the verification environment. To keep these tests offline and
deterministic *without changing topics.py's runtime behaviour*, we install
lightweight stub modules into ``sys.modules`` for ``kafka``, ``kafka.admin``,
``kafka.errors`` and ``aws_msk_iam_sasl_signer`` BEFORE importing topics. The
stubs provide dummy KafkaAdminClient/NewTopic classes and REAL Exception
subclasses for KafkaError/TopicAlreadyExistsError so ``except`` clauses in
topics.py behave exactly as they would against the real library.

topics.py was NOT modified; the sys.modules-stub approach keeps the source
untouched.

Runner: pytest (bare-assert, function-style — matches
cdc-prepare-mariadb/tests/test_prepare.py).

Property-based test: Hypothesis is used when installed (Property 3, min 100
iterations); otherwise a seeded >=100-iteration loop is used. The active
strategy is recorded on the test via a module-level flag and in its docstring.
"""

from __future__ import annotations

import io
import json
import sys
import types
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

import pytest


# --------------------------------------------------------------------------- #
# Install kafka / signer stubs into sys.modules BEFORE importing topics.       #
# The real library is not required to be present in this environment.          #
# --------------------------------------------------------------------------- #


class StubKafkaError(Exception):
    """Stand-in for kafka.errors.KafkaError (a real Exception subclass)."""


class StubTopicAlreadyExistsError(StubKafkaError):
    """Stand-in for kafka.errors.TopicAlreadyExistsError."""


class StubNewTopic:
    """Records the arguments topics.to_new_topic passes, offline."""

    def __init__(self, name, num_partitions, replication_factor, topic_configs=None):
        self.name = name
        self.num_partitions = num_partitions
        self.replication_factor = replication_factor
        self.topic_configs = dict(topic_configs or {})


class StubKafkaAdminClient:
    """Default stub admin client; tests inject mocks via build_admin_client."""

    def __init__(self, **kwargs):
        self.kwargs = kwargs

    def create_topics(self, *args, **kwargs):
        return None

    def close(self):
        return None


class StubMSKAuthTokenProvider:
    """Stand-in for aws_msk_iam_sasl_signer.MSKAuthTokenProvider."""

    @staticmethod
    def generate_auth_token(region):
        return ("stub-token", 0)


def _install_kafka_stubs():
    kafka_mod = types.ModuleType("kafka")

    admin_mod = types.ModuleType("kafka.admin")
    admin_mod.KafkaAdminClient = StubKafkaAdminClient
    admin_mod.NewTopic = StubNewTopic

    errors_mod = types.ModuleType("kafka.errors")
    errors_mod.KafkaError = StubKafkaError
    errors_mod.TopicAlreadyExistsError = StubTopicAlreadyExistsError

    kafka_mod.admin = admin_mod
    kafka_mod.errors = errors_mod

    signer_mod = types.ModuleType("aws_msk_iam_sasl_signer")
    signer_mod.MSKAuthTokenProvider = StubMSKAuthTokenProvider

    sys.modules.setdefault("kafka", kafka_mod)
    sys.modules.setdefault("kafka.admin", admin_mod)
    sys.modules.setdefault("kafka.errors", errors_mod)
    sys.modules.setdefault("aws_msk_iam_sasl_signer", signer_mod)


_install_kafka_stubs()

# topics.py lives one directory up and is a top-level module (not a package),
# so make its directory importable regardless of where pytest is invoked from.
_PROJECT_DIR = Path(__file__).resolve().parent.parent
if str(_PROJECT_DIR) not in sys.path:
    sys.path.insert(0, str(_PROJECT_DIR))

import topics  # noqa: E402  (stubs + path set up above)

# The exception types topics.py actually bound at import time (our stubs).
TopicAlreadyExistsError = topics.TopicAlreadyExistsError
KafkaError = topics.KafkaError


# --------------------------------------------------------------------------- #
# Optional Hypothesis; fall back to a seeded loop when not installed.          #
# --------------------------------------------------------------------------- #

try:
    from hypothesis import HealthCheck, given, settings
    from hypothesis import strategies as st

    HAVE_HYPOTHESIS = True
except ImportError:  # pragma: no cover - environment-dependent
    HAVE_HYPOTHESIS = False


# --------------------------------------------------------------------------- #
# A mock admin client that raises TopicAlreadyExistsError for named topics     #
# and records every call, so tests can assert no alter/config API was hit.     #
# --------------------------------------------------------------------------- #


class RecordingAdmin:
    """Kafka admin double: create_topics raises AlreadyExists for known names.

    ``existing`` is the set of topic names the cluster already holds. Any
    alter/config-mutating API access is recorded in ``forbidden_calls`` via
    ``__getattr__`` so a test can assert none was ever invoked (Property 3).
    """

    # Any of these being accessed/called would mean configuration was touched.
    _FORBIDDEN = (
        "alter_configs",
        "incremental_alter_configs",
        "alter_topic",
        "alter_topics",
        "create_partitions",
    )

    def __init__(self, existing=()):
        self.existing = set(existing)
        self.created = []          # names for which create_topics succeeded
        self.already_existed = []  # names that raised AlreadyExists
        self.forbidden_calls = []  # any alter/config API touched
        self.closed = False

    def create_topics(self, new_topics, validate_only=False):
        for nt in new_topics:
            if nt.name in self.existing:
                self.already_existed.append(nt.name)
                raise TopicAlreadyExistsError(f"{nt.name} exists")
            self.created.append(nt.name)
        return None

    def close(self):
        self.closed = True

    def __getattr__(self, name):
        if name in self._FORBIDDEN:
            def _record(*args, **kwargs):
                self.forbidden_calls.append((name, args, kwargs))
                return None

            return _record
        raise AttributeError(name)


# --------------------------------------------------------------------------- #
# 1. Property 3 — topic idempotency leaves existing configuration untouched.   #
#    Validates: Requirements 4.6                                               #
# --------------------------------------------------------------------------- #

_PROPERTY_3_TAG = (
    "Feature: debezium, Property 3: Topic idempotency leaves existing "
    "configuration untouched"
)


def _check_idempotency(topic_list, existing_names):
    """Core assertion body shared by the property and the concrete case.

    Runs create_topics against a RecordingAdmin that raises AlreadyExists for
    ``existing_names``. Asserts every requested topic is accounted for as either
    created or already-existing (i.e. AlreadyExists is SUCCESS, never an error),
    and that NO alter/config-mutating API was ever invoked.
    """
    requested = [t["name"] for t in topic_list]
    present = {n for n in existing_names if n in requested}
    admin = RecordingAdmin(existing=present)

    # Must not raise: an already-existing topic is success (Req 4.6).
    topics.create_topics(admin, topic_list)

    # No configuration was altered on any pre-existing (or new) topic.
    assert admin.forbidden_calls == []

    # Every requested topic is either freshly created or reported as existing;
    # existing ones are left unmodified (skipped), never re-created.
    assert set(admin.created) == set(requested) - present
    assert set(admin.already_existed) == present


if HAVE_HYPOTHESIS:

    _name_st = st.text(
        alphabet="abcdefghijklmnopqrstuvwxyz0123456789-._",
        min_size=1,
        max_size=20,
    )
    _config_key_st = st.sampled_from(
        ["cleanup.policy", "retention.ms", "retention.bytes", "segment.bytes"]
    )
    _topic_st = st.builds(
        lambda name, partitions, configs: {
            "name": name,
            "partitions": partitions,
            "configs": configs,
        },
        name=_name_st,
        partitions=st.integers(min_value=1, max_value=50),
        configs=st.dictionaries(_config_key_st, st.text(max_size=12), max_size=4),
    )

    @settings(max_examples=100, deadline=None, suppress_health_check=[HealthCheck.too_slow])
    @given(
        topic_list=st.lists(_topic_st, min_size=0, max_size=8, unique_by=lambda t: t["name"]),
        existing_ratio=st.floats(min_value=0.0, max_value=1.0),
    )
    def test_property_3_topic_idempotency_untouched(topic_list, existing_ratio):
        """Feature: debezium, Property 3: Topic idempotency leaves existing
        configuration untouched (Req 4.6). Hypothesis, min 100 examples.

        For any topic list and any cluster already holding a topic of the same
        name, create_topics treats the existing topic as success and alters no
        configuration.
        """
        names = [t["name"] for t in topic_list]
        cut = int(len(names) * existing_ratio)
        existing = set(names[:cut])
        _check_idempotency(topic_list, existing)

    PROPERTY_3_STRATEGY = "hypothesis"

else:  # pragma: no cover - only when Hypothesis is absent

    def test_property_3_topic_idempotency_untouched():
        """Feature: debezium, Property 3: Topic idempotency leaves existing
        configuration untouched (Req 4.6). Seeded loop, 100 iterations."""
        import random

        rng = random.Random(20240611)
        config_keys = ["cleanup.policy", "retention.ms", "retention.bytes", "segment.bytes"]
        alphabet = "abcdefghijklmnopqrstuvwxyz0123456789-._"

        for _ in range(100):
            n = rng.randint(0, 8)
            names = []
            topic_list = []
            while len(topic_list) < n:
                name = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 20)))
                if name in names:
                    continue
                names.append(name)
                configs = {
                    rng.choice(config_keys): str(rng.randint(0, 10_000))
                    for _ in range(rng.randint(0, 4))
                }
                topic_list.append(
                    {
                        "name": name,
                        "partitions": rng.randint(1, 50),
                        "configs": configs,
                    }
                )
            cut = rng.randint(0, len(names))
            existing = set(names[:cut])
            _check_idempotency(topic_list, existing)

    PROPERTY_3_STRATEGY = "seeded-loop"


# --------------------------------------------------------------------------- #
# 2. Concrete case behind Property 3: an existing topic is success, no change. #
# --------------------------------------------------------------------------- #


def test_existing_topic_is_success_with_no_config_change():
    admin = RecordingAdmin(existing={"cdc.history"})
    topic_list = [
        {"name": "cdc.history", "partitions": 1, "configs": {"cleanup.policy": "compact"}},
        {"name": "cdc.offsets", "partitions": 3, "configs": {"retention.ms": "604800000"}},
    ]

    out = io.StringIO()
    with redirect_stdout(out):
        topics.create_topics(admin, topic_list)  # must not raise

    # New topic created, existing one skipped, nothing altered.
    assert admin.created == ["cdc.offsets"]
    assert admin.already_existed == ["cdc.history"]
    assert admin.forbidden_calls == []
    assert "already exists" in out.getvalue()


# --------------------------------------------------------------------------- #
# 3. Unreachable cluster exits non-zero (Req 4.10) via the _fail path.         #
# --------------------------------------------------------------------------- #


def test_unreachable_cluster_build_admin_client_aborts_nonzero(monkeypatch):
    """When build_admin_client raises a KafkaError, main() aborts via _fail
    (sys.exit(1)) with a descriptive stderr message (Req 4.10)."""
    monkeypatch.setenv("PROPELLER_INPUT_bootstrap_servers", "broker.invalid:9092")
    monkeypatch.setenv("PROPELLER_INPUT_security_protocol", "PLAINTEXT")
    monkeypatch.setenv("PROPELLER_INPUT_topics", "[]")

    def _boom(*args, **kwargs):
        raise KafkaError("connection refused")

    monkeypatch.setattr(topics, "build_admin_client", _boom)

    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.main()

    assert exc.value.code == 1
    message = err.getvalue()
    assert "could not connect" in message
    assert "broker.invalid:9092" in message


def test_create_topics_kafka_error_aborts_nonzero(monkeypatch):
    """A KafkaError raised while creating topics also aborts non-zero (Req 4.10)."""
    monkeypatch.setenv("PROPELLER_INPUT_bootstrap_servers", "broker.internal:9092")
    monkeypatch.setenv("PROPELLER_INPUT_security_protocol", "PLAINTEXT")
    monkeypatch.setenv("PROPELLER_INPUT_topics", '[{"name": "t1"}]')

    admin = mock.MagicMock()
    admin.create_topics.side_effect = KafkaError("broker down")
    monkeypatch.setattr(topics, "build_admin_client", lambda *a, **k: admin)

    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.main()

    assert exc.value.code == 1
    assert "failed creating topics" in err.getvalue()
    # The client is always closed in the finally block.
    admin.close.assert_called_once()


# --------------------------------------------------------------------------- #
# 4. SASL_SSL/IAM path uses the OAUTHBEARER token provider; PLAINTEXT doesn't. #
#    Validates: Requirement 4.11                                               #
# --------------------------------------------------------------------------- #


def test_sasl_ssl_builds_client_with_oauthbearer_token_provider(monkeypatch):
    """SASL_SSL builds the admin client with sasl_mechanism=OAUTHBEARER and a
    token provider obtained from build_token_provider (Req 4.11)."""
    captured = {}

    def _fake_admin(**kwargs):
        captured.update(kwargs)
        return StubKafkaAdminClient(**kwargs)

    sentinel_provider = object()
    monkeypatch.setattr(topics, "build_token_provider", lambda region: sentinel_provider)
    # topics.py bound KafkaAdminClient at import; patch that name directly.
    monkeypatch.setattr(topics, "KafkaAdminClient", _fake_admin)

    client = topics.build_admin_client(
        "b1:9092,b2:9092", "SASL_SSL", region="eu-west-1"
    )

    assert isinstance(client, StubKafkaAdminClient)
    assert captured["security_protocol"] == "SASL_SSL"
    assert captured["sasl_mechanism"] == "OAUTHBEARER"
    assert captured["sasl_oauth_token_provider"] is sentinel_provider
    assert captured["bootstrap_servers"] == ["b1:9092", "b2:9092"]


def test_build_token_provider_uses_msk_iam_signer(monkeypatch):
    """build_token_provider returns a provider whose token() calls the AWS MSK
    IAM signer generate_auth_token for the given region."""
    calls = []

    class _Signer:
        @staticmethod
        def generate_auth_token(region):
            calls.append(region)
            return ("iam-token-xyz", 12345)

    signer_mod = sys.modules["aws_msk_iam_sasl_signer"]
    monkeypatch.setattr(signer_mod, "MSKAuthTokenProvider", _Signer)

    provider = topics.build_token_provider("eu-west-1")
    assert provider.token() == "iam-token-xyz"
    assert calls == ["eu-west-1"]


def test_plaintext_does_not_require_signer(monkeypatch):
    """A PLAINTEXT run builds the client with no SASL and never imports/calls
    the IAM token provider (Req 4.11)."""
    captured = {}

    def _fake_admin(**kwargs):
        captured.update(kwargs)
        return StubKafkaAdminClient(**kwargs)

    def _fail_provider(region):  # pragma: no cover - must never be called
        raise AssertionError("build_token_provider must not be called for PLAINTEXT")

    monkeypatch.setattr(topics, "KafkaAdminClient", _fake_admin)
    monkeypatch.setattr(topics, "build_token_provider", _fail_provider)

    client = topics.build_admin_client("b1:9092", "PLAINTEXT", region=None)

    assert isinstance(client, StubKafkaAdminClient)
    assert captured["security_protocol"] == "PLAINTEXT"
    assert "sasl_mechanism" not in captured
    assert "sasl_oauth_token_provider" not in captured


# --------------------------------------------------------------------------- #
# 5. read_inputs — security_protocol required/validated, topics JSON parsing.  #
# --------------------------------------------------------------------------- #


def _env(**overrides):
    """Build an inputs env dict; pass a key as None to omit it."""
    base = {
        "PROPELLER_INPUT_bootstrap_servers": "broker:9092",
        "PROPELLER_INPUT_security_protocol": "PLAINTEXT",
        "PROPELLER_INPUT_topics": "[]",
    }
    base.update(overrides)
    return {k: v for k, v in base.items() if v is not None}


def test_read_inputs_missing_bootstrap_servers_exits_nonzero():
    with pytest.raises(SystemExit) as exc:
        topics.read_inputs(env=_env(PROPELLER_INPUT_bootstrap_servers=None))
    assert exc.value.code == 1


def test_read_inputs_security_protocol_required_no_default():
    """security_protocol has no default; missing → SystemExit non-zero."""
    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.read_inputs(env=_env(PROPELLER_INPUT_security_protocol=None))
    assert exc.value.code == 1
    assert "security_protocol" in err.getvalue()
    assert "no default" in err.getvalue()


def test_read_inputs_security_protocol_invalid_value_exits():
    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.read_inputs(env=_env(PROPELLER_INPUT_security_protocol="SSL"))
    assert exc.value.code == 1
    assert "must be one of" in err.getvalue()


def test_read_inputs_accepts_both_valid_protocols():
    for protocol in ("PLAINTEXT", "SASL_SSL"):
        servers, parsed, security_protocol = topics.read_inputs(
            env=_env(PROPELLER_INPUT_security_protocol=protocol)
        )
        assert servers == "broker:9092"
        assert parsed == []
        assert security_protocol == protocol


def test_read_inputs_parses_topics_json():
    env = _env(
        PROPELLER_INPUT_topics='[{"name": "t1", "partitions": 3, "configs": {"cleanup.policy": "compact"}}]'
    )
    _servers, parsed, _protocol = topics.read_inputs(env=env)
    assert parsed == [
        {"name": "t1", "partitions": 3, "configs": {"cleanup.policy": "compact"}}
    ]


def test_read_inputs_bad_topics_json_exits():
    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.read_inputs(env=_env(PROPELLER_INPUT_topics="{not json"))
    assert exc.value.code == 1
    assert "not valid JSON" in err.getvalue()


def test_read_inputs_topics_not_a_list_exits():
    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.read_inputs(env=_env(PROPELLER_INPUT_topics='{"name": "t1"}'))
    assert exc.value.code == 1
    assert "must be a JSON list" in err.getvalue()


# --------------------------------------------------------------------------- #
# 6. PROPELLER_INPUT_topics_file — reads a topics list from disk, relative to #
#    project_dir; mutually exclusive with PROPELLER_INPUT_topics.             #
# --------------------------------------------------------------------------- #


def test_read_inputs_topics_file_is_read_relative_to_project_dir(tmp_path):
    topic_list = [{"name": "schema-history.x", "partitions": 1, "configs": {"cleanup.policy": "delete"}}]
    (tmp_path / "topics.json").write_text(json.dumps(topic_list))

    env = _env(PROPELLER_INPUT_topics=None, PROPELLER_INPUT_topics_file="topics.json")
    _servers, parsed, _protocol = topics.read_inputs(env=env, project_dir=tmp_path)

    assert parsed == topic_list


def test_read_inputs_topics_file_and_topics_are_mutually_exclusive(tmp_path):
    (tmp_path / "topics.json").write_text("[]")
    env = _env(PROPELLER_INPUT_topics="[]", PROPELLER_INPUT_topics_file="topics.json")

    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.read_inputs(env=env, project_dir=tmp_path)
    assert exc.value.code == 1
    assert "mutually exclusive" in err.getvalue()


def test_read_inputs_topics_file_missing_exits_nonzero(tmp_path):
    env = _env(PROPELLER_INPUT_topics=None, PROPELLER_INPUT_topics_file="does-not-exist.json")

    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.read_inputs(env=env, project_dir=tmp_path)
    assert exc.value.code == 1
    assert "does-not-exist.json" in err.getvalue()
    assert "could not be read" in err.getvalue()


def test_read_inputs_topics_file_bad_json_exits_nonzero(tmp_path):
    (tmp_path / "topics.json").write_text("{not json")
    env = _env(PROPELLER_INPUT_topics=None, PROPELLER_INPUT_topics_file="topics.json")

    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.read_inputs(env=env, project_dir=tmp_path)
    assert exc.value.code == 1
    assert "PROPELLER_INPUT_topics_file" in err.getvalue()
    assert "not valid JSON" in err.getvalue()


def test_read_inputs_topics_file_not_a_list_exits_nonzero(tmp_path):
    (tmp_path / "topics.json").write_text('{"name": "t1"}')
    env = _env(PROPELLER_INPUT_topics=None, PROPELLER_INPUT_topics_file="topics.json")

    err = io.StringIO()
    with redirect_stderr(err):
        with pytest.raises(SystemExit) as exc:
            topics.read_inputs(env=env, project_dir=tmp_path)
    assert exc.value.code == 1
    assert "PROPELLER_INPUT_topics_file" in err.getvalue()
    assert "must be a JSON list" in err.getvalue()


def test_read_inputs_neither_topics_source_creates_nothing(tmp_path):
    env = _env(PROPELLER_INPUT_topics=None, PROPELLER_INPUT_topics_file=None)
    _servers, parsed, _protocol = topics.read_inputs(env=env, project_dir=tmp_path)
    assert parsed == []


def test_read_inputs_default_project_dir_is_this_files_directory():
    """With no project_dir override, a relative topics_file resolves against
    the real project directory — the *.json.example files ship there."""
    env = _env(
        PROPELLER_INPUT_topics=None,
        PROPELLER_INPUT_topics_file="topics-schema-history-only.json.example",
    )
    _servers, parsed, _protocol = topics.read_inputs(env=env)
    assert len(parsed) == 1
    assert parsed[0]["name"] == "schema-history.my-connector"


def test_read_inputs_oracle_example_config_is_the_documented_shape():
    """topics-oracle-recommended.json.example carries the same superset
    (schema history + the three Connect internal topics) as the MariaDB
    example, with an Oracle-flavoured schema history topic name."""
    env = _env(
        PROPELLER_INPUT_topics=None,
        PROPELLER_INPUT_topics_file="topics-oracle-recommended.json.example",
    )
    _servers, parsed, _protocol = topics.read_inputs(env=env)
    names = [t["name"] for t in parsed]
    assert names == [
        "schema-history.oracle.ORCLPDB1",
        "connect-offsets",
        "connect-configs",
        "connect-status",
    ]
    history = parsed[0]
    assert history["partitions"] == 1
    assert history["configs"] == {
        "cleanup.policy": "delete",
        "retention.ms": "-1",
        "retention.bytes": "-1",
    }
