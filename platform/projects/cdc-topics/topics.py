"""Create the Kafka topics a Debezium connector needs.

This project runs on an In_VPC_Runner with no internet route, so it relies only
on libraries baked into the deploy-runner image.

Everything environment-specific arrives as a ``PROPELLER_INPUT_*`` environment
variable; nothing about the bootstrap servers, topic names, security protocol,
account or region is hardcoded:

- ``PROPELLER_INPUT_bootstrap_servers``  (required) comma-separated broker list.
- ``PROPELLER_INPUT_topics``             a JSON list of ``{name, partitions, configs}``.
- ``PROPELLER_INPUT_topics_file``        path to a JSON file holding the same
  shape as ``PROPELLER_INPUT_topics``, relative to this project's directory.
  Mutually exclusive with ``PROPELLER_INPUT_topics``. See ``*.json.example``
  in this directory and the README for ready-made configs.
- ``PROPELLER_INPUT_security_protocol``  (required, no default) ``PLAINTEXT`` or ``SASL_SSL``.

Behaviour: each requested topic is created with its partitions and configs. An
already-existing topic is treated as success and its configuration is left
unchanged. Cluster-wide configuration is never modified and automatic
topic creation is never enabled. If the cluster is unreachable the run
aborts with a descriptive error and a non-zero exit. ``destroy``
deletes nothing — that lives in the justfile.
"""

import json
import os
import sys
from pathlib import Path

from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import KafkaError, TopicAlreadyExistsError

VALID_SECURITY_PROTOCOLS = ("PLAINTEXT", "SASL_SSL")


def _fail(message):
    """Print a descriptive error to stderr and exit non-zero."""
    print(f"cdc-topics: {message}", file=sys.stderr)
    sys.exit(1)


def read_inputs(env=None, project_dir=None):
    """Read and validate the PROPELLER_INPUT_* inputs.

    Returns a tuple of (bootstrap_servers, topics, security_protocol). Fails
    fast if a required input is missing or the security protocol is not one of
    the two accepted values (Req 4.8; no default per design open-item 5).

    ``project_dir`` is where a relative ``PROPELLER_INPUT_topics_file`` is
    resolved against; defaults to this file's directory. Overridable so tests
    can point it at a fixture directory without touching cwd.
    """
    env = os.environ if env is None else env
    project_dir = Path(__file__).resolve().parent if project_dir is None else Path(project_dir)

    bootstrap_servers = env.get("PROPELLER_INPUT_bootstrap_servers")
    if not bootstrap_servers:
        _fail("PROPELLER_INPUT_bootstrap_servers is required")

    security_protocol = env.get("PROPELLER_INPUT_security_protocol")
    if not security_protocol:
        _fail(
            "PROPELLER_INPUT_security_protocol is required and has no default; "
            f"set one of {VALID_SECURITY_PROTOCOLS}"
        )
    if security_protocol not in VALID_SECURITY_PROTOCOLS:
        _fail(
            f"PROPELLER_INPUT_security_protocol must be one of "
            f"{VALID_SECURITY_PROTOCOLS}, got {security_protocol!r}"
        )

    topics = read_topics(env, project_dir)

    return bootstrap_servers, topics, security_protocol


def read_topics(env, project_dir):
    """Resolve the ``topics`` input, inline or from a file.

    ``PROPELLER_INPUT_topics`` (a JSON string) and ``PROPELLER_INPUT_topics_file``
    (a path to a JSON file, relative to ``project_dir``) are mutually exclusive;
    setting neither means create nothing. Isolated from read_inputs so each
    source can be tested independently.
    """
    inline_raw = env.get("PROPELLER_INPUT_topics", "")
    file_path = env.get("PROPELLER_INPUT_topics_file", "")

    if inline_raw and file_path:
        _fail(
            "PROPELLER_INPUT_topics and PROPELLER_INPUT_topics_file are "
            "mutually exclusive; set at most one"
        )

    if file_path:
        full_path = project_dir / file_path
        try:
            topics_raw = full_path.read_text()
        except OSError as exc:
            _fail(f"PROPELLER_INPUT_topics_file {file_path!r} could not be read: {exc}")
    else:
        topics_raw = inline_raw or "[]"

    try:
        topics = json.loads(topics_raw)
    except json.JSONDecodeError as exc:
        source = f"PROPELLER_INPUT_topics_file ({file_path})" if file_path else "PROPELLER_INPUT_topics"
        _fail(f"{source} is not valid JSON: {exc}")
    if not isinstance(topics, list):
        source = "PROPELLER_INPUT_topics_file" if file_path else "PROPELLER_INPUT_topics"
        _fail(f"{source} must be a JSON list of {{name, partitions, configs}}")

    return topics


def build_token_provider(region):
    """Build the AWS MSK IAM SASL/OAUTHBEARER token provider.

    The signer is imported here rather than at module load so a PLAINTEXT run
    never requires ``aws-msk-iam-sasl-signer-python`` (Req 4.11). Isolated in
    its own function so tests can patch it without a real signer.
    """
    from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

    class _IAMTokenProvider:
        def token(self):
            token, _expiry_ms = MSKAuthTokenProvider.generate_auth_token(region)
            return token

    return _IAMTokenProvider()


def build_admin_client(bootstrap_servers, security_protocol, region=None):
    """Construct the KafkaAdminClient in one place (Req 4.8, 4.11).

    Isolated so task 1.29's tests can patch this single function to inject a
    mock admin client. For SASL_SSL the client uses SASL/OAUTHBEARER backed by
    the AWS MSK IAM token provider; for PLAINTEXT it uses no SASL at all.
    """
    servers = [s.strip() for s in bootstrap_servers.split(",") if s.strip()]

    if security_protocol == "SASL_SSL":
        return KafkaAdminClient(
            bootstrap_servers=servers,
            security_protocol="SASL_SSL",
            sasl_mechanism="OAUTHBEARER",
            sasl_oauth_token_provider=build_token_provider(region),
        )

    return KafkaAdminClient(
        bootstrap_servers=servers,
        security_protocol="PLAINTEXT",
    )


def to_new_topic(topic):
    """Translate one input topic dict into a kafka-python NewTopic.

    ``partitions`` defaults to 1 and ``configs`` to an empty map; whatever
    configs the consumer supplies (e.g. cleanup.policy, retention.ms,
    retention.bytes) are applied faithfully and never hardcoded here.
    """
    name = topic.get("name")
    if not name:
        _fail("each topic must have a 'name'")
    return NewTopic(
        name=name,
        num_partitions=int(topic.get("partitions", 1)),
        replication_factor=-1,
        topic_configs=dict(topic.get("configs") or {}),
    )


def create_topics(admin, topics):
    """Create each topic; an already-existing topic is success.

    Topics are created one at a time so that an AlreadyExists on one does not
    prevent the others from being created, and so an existing topic's
    configuration is never altered — it is simply reported and skipped.
    """
    for topic in topics:
        new_topic = to_new_topic(topic)
        try:
            admin.create_topics(new_topics=[new_topic], validate_only=False)
            print(f"cdc-topics: created topic {new_topic.name}")
        except TopicAlreadyExistsError:
            print(
                f"cdc-topics: topic {new_topic.name} already exists; "
                "left unmodified"
            )


def main():
    bootstrap_servers, topics, security_protocol = read_inputs()
    region = os.environ.get("AWS_REGION")

    try:
        admin = build_admin_client(bootstrap_servers, security_protocol, region)
    except KafkaError as exc:
        _fail(f"could not connect to Kafka cluster at {bootstrap_servers}: {exc}")

    try:
        create_topics(admin, topics)
    except KafkaError as exc:
        _fail(f"failed creating topics on {bootstrap_servers}: {exc}")
    finally:
        try:
            admin.close()
        except Exception:
            pass

    print(f"cdc-topics: done ({len(topics)} topic(s) requested)")


if __name__ == "__main__":
    main()
