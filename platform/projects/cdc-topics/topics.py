#!/usr/bin/env python3
"""Create the Kafka topics a Debezium connector needs.

Inputs (PROPELLER_INPUT_*):

- bootstrap_servers   required, comma-separated broker list.
- security_protocol   required, PLAINTEXT or SASL_SSL. SASL_SSL uses MSK IAM
                      auth (AWS_MSK_IAM, credentials from the runner role).
- topics              a JSON list of {name, partitions, configs}, or
- topics_file         a JSON file with the same list, relative to this
                      project. Set at most one; neither creates nothing.

An existing topic is left unchanged. Cluster settings are never changed.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path

from kafka.admin import KafkaAdminClient
from kafka.errors import KafkaError, TopicAlreadyExistsError

PREFIX = "PROPELLER_INPUT_"
SECURITY_PROTOCOLS = ("PLAINTEXT", "SASL_SSL")
PROJECT_DIR = Path(__file__).resolve().parent


class InputError(Exception):
    """A missing or malformed input. Exit code 2."""


@dataclass(frozen=True)
class Topic:
    name: str
    partitions: int
    configs: dict[str, str]


@dataclass(frozen=True)
class Inputs:
    bootstrap_servers: list[str]
    security_protocol: str
    topics: list[Topic]


def read_inputs(env=os.environ, project_dir: Path = PROJECT_DIR) -> Inputs:
    servers = [s.strip() for s in env.get(PREFIX + "bootstrap_servers", "").split(",") if s.strip()]
    if not servers:
        raise InputError(f"missing required input: {PREFIX}bootstrap_servers")
    # No default: a wrong guess fails late and obscurely against the other cluster shape.
    protocol = env.get(PREFIX + "security_protocol", "")
    if protocol not in SECURITY_PROTOCOLS:
        raise InputError(f"{PREFIX}security_protocol must be one of {SECURITY_PROTOCOLS}, got {protocol!r}")
    return Inputs(servers, protocol, read_topics(env, project_dir))


def read_topics(env, project_dir: Path) -> list[Topic]:
    inline = env.get(PREFIX + "topics", "")
    file = env.get(PREFIX + "topics_file", "")
    if inline and file:
        raise InputError(f"{PREFIX}topics and {PREFIX}topics_file are mutually exclusive")
    source = f"{PREFIX}topics_file ({file})" if file else f"{PREFIX}topics"
    try:
        raw = (project_dir / file).read_text() if file else (inline or "[]")
        doc = json.loads(raw)
    except OSError as exc:
        raise InputError(f"{source} cannot be read: {exc}") from None
    except ValueError as exc:
        raise InputError(f"{source} is not valid JSON: {exc}") from None
    if not isinstance(doc, list):
        raise InputError(f"{source} must be a JSON list of {{name, partitions, configs}}")

    topics = []
    for item in doc:
        if not isinstance(item, dict) or not item.get("name"):
            raise InputError(f"{source}: each topic needs a 'name'")
        try:
            partitions = int(item.get("partitions", 1))
        except (TypeError, ValueError):
            raise InputError(f"{source}: {item['name']}.partitions must be an integer") from None
        configs = {str(k): str(v) for k, v in (item.get("configs") or {}).items()}
        topics.append(Topic(str(item["name"]), partitions, configs))
    return topics


def admin_client(inputs: Inputs) -> KafkaAdminClient:
    if inputs.security_protocol == "SASL_SSL":
        # Built into kafka-python; signs with botocore (runner role, AWS_REGION).
        return KafkaAdminClient(
            bootstrap_servers=inputs.bootstrap_servers,
            security_protocol="SASL_SSL",
            sasl_mechanism="AWS_MSK_IAM",
        )
    return KafkaAdminClient(bootstrap_servers=inputs.bootstrap_servers, security_protocol="PLAINTEXT")


def create_topics(admin, topics: list[Topic]) -> None:
    """Create each topic. One at a time, so an existing topic does not stop the
    others. The replication factor is the cluster default."""
    for topic in topics:
        spec = {topic.name: {"num_partitions": topic.partitions, "configs": topic.configs}}
        try:
            admin.create_topics(spec)
            print(f"cdc-topics: created {topic.name}")
        except TopicAlreadyExistsError:
            print(f"cdc-topics: {topic.name} exists, left unchanged")


def main() -> int:
    try:
        inputs = read_inputs()
    except InputError as exc:
        print(f"cdc-topics: {exc}", file=sys.stderr)
        return 2
    servers = ",".join(inputs.bootstrap_servers)
    try:
        admin = admin_client(inputs)
        try:
            create_topics(admin, inputs.topics)
        finally:
            admin.close()
    except KafkaError as exc:
        print(f"cdc-topics: Kafka error on {servers}: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1
    print(f"cdc-topics: done ({len(inputs.topics)} topic(s) requested)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
