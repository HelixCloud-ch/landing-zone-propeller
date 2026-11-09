"""Tests for cdc-topics/topics.py, with a fake admin client.

Run: uv run --project platform/shared/python/cdc pytest platform/projects/cdc-topics
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest
from kafka.errors import KafkaTimeoutError, TopicAlreadyExistsError

PROJECT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_DIR))
import topics  # noqa: E402

P = topics.PREFIX

@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    """Tests see only the inputs they set."""
    for key in list(os.environ):
        if key.startswith("PROPELLER_INPUT_"):
            monkeypatch.delenv(key)

TOPICS = [{"name": "schema-history.db1", "partitions": 1, "configs": {"retention.ms": -1}}]


class FakeAdmin:
    def __init__(self, existing=()):
        self.existing = set(existing)
        self.created: list[dict] = []
        self.closed = False

    def create_topics(self, spec):
        (name,) = spec
        if name in self.existing:
            raise TopicAlreadyExistsError(name)
        self.created.append(spec)

    def close(self):
        self.closed = True


def env(**values):
    return {P + k: v for k, v in values.items()}


BASE = {"bootstrap_servers": "b-1:9098, b-2:9098", "security_protocol": "SASL_SSL"}


# ── Inputs ───────────────────────────────────────────────────────────────────


def test_inline_topics():
    inputs = topics.read_inputs(env(**BASE, topics=json.dumps(TOPICS)))
    assert inputs.bootstrap_servers == ["b-1:9098", "b-2:9098"]
    assert inputs.topics == [topics.Topic("schema-history.db1", 1, {"retention.ms": "-1"})]


def test_topics_file_is_relative_to_the_project(tmp_path):
    (tmp_path / "topics.json").write_text(json.dumps(TOPICS))
    inputs = topics.read_inputs(env(**BASE, topics_file="topics.json"), tmp_path)
    assert inputs.topics[0].name == "schema-history.db1"


def test_example_files_are_valid():
    for example in PROJECT_DIR.glob("*.json.example"):
        topics.read_topics(env(topics_file=example.name), PROJECT_DIR)


def test_no_topics_means_none():
    assert topics.read_inputs(env(**BASE)).topics == []


@pytest.mark.parametrize("values, message", [
    ({"security_protocol": "SASL_SSL"}, "bootstrap_servers"),
    ({"bootstrap_servers": "b:9092"}, "security_protocol must be one of"),
    ({**BASE, "security_protocol": "SSL"}, "security_protocol must be one of"),
    ({**BASE, "topics": "[]", "topics_file": "x.json"}, "mutually exclusive"),
    ({**BASE, "topics": "{not json"}, "not valid JSON"),
    ({**BASE, "topics": "{}"}, "must be a JSON list"),
    ({**BASE, "topics": '[{"partitions": 1}]'}, "needs a 'name'"),
    ({**BASE, "topics": '[{"name": "t", "partitions": "x"}]'}, "must be an integer"),
    ({**BASE, "topics_file": "missing.json"}, "cannot be read"),
])
def test_bad_inputs(values, message, tmp_path):
    with pytest.raises(topics.InputError, match=message):
        topics.read_inputs(env(**values), tmp_path)


# ── Admin client and creation ────────────────────────────────────────────────


@pytest.mark.parametrize("protocol, expected", [
    ("SASL_SSL", {"security_protocol": "SASL_SSL", "sasl_mechanism": "AWS_MSK_IAM"}),
    ("PLAINTEXT", {"security_protocol": "PLAINTEXT"}),
])
def test_admin_client_settings(monkeypatch, protocol, expected):
    captured = {}
    monkeypatch.setattr(topics, "KafkaAdminClient", lambda **kw: captured.update(kw))
    topics.admin_client(topics.Inputs(["b:1"], protocol, []))
    assert captured == {"bootstrap_servers": ["b:1"], **expected}


def test_existing_topic_is_left_unchanged_and_others_are_created(capsys):
    admin = FakeAdmin(existing={"a"})
    topics.create_topics(admin, [topics.Topic("a", 1, {}), topics.Topic("b", 3, {"cleanup.policy": "compact"})])
    assert admin.created == [{"b": {"num_partitions": 3, "configs": {"cleanup.policy": "compact"}}}]
    assert "a exists, left unchanged" in capsys.readouterr().out


def test_main_creates_topics_and_closes(monkeypatch):
    admin = FakeAdmin()
    for key, value in {**BASE, "topics": json.dumps(TOPICS)}.items():
        monkeypatch.setenv(P + key, value)
    monkeypatch.setattr(topics, "admin_client", lambda inputs: admin)
    assert topics.main() == 0
    assert len(admin.created) == 1 and admin.closed


def test_main_reports_kafka_errors(monkeypatch, capsys):
    for key, value in BASE.items():
        monkeypatch.setenv(P + key, value)

    def unreachable(inputs):
        raise KafkaTimeoutError()

    monkeypatch.setattr(topics, "admin_client", unreachable)
    assert topics.main() == 1
    assert "KafkaTimeoutError" in capsys.readouterr().err


def test_main_exits_2_on_bad_input(monkeypatch):
    monkeypatch.delenv(P + "bootstrap_servers", raising=False)
    assert topics.main() == 2
