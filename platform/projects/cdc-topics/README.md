# cdc-topics

Creates the Kafka topics a Debezium connector needs. It has no Terraform
state. `apply` runs `topics.py` in the shared `cdc` Python env
(`platform/shared/python/cdc`) through `py-run`.

- It creates each requested topic. An existing topic is left unchanged, also
  when its settings differ.
- It never changes cluster settings and never enables automatic topic
  creation.
- `destroy` does nothing: deleting a topic loses the schema history and the
  offsets, and forces a new snapshot. Delete topics manually if you need to.

## Inputs

Inputs arrive as `PROPELLER_INPUT_*` variables.

- `bootstrap_servers`: required. Comma-separated broker list.
- `security_protocol`: required, `PLAINTEXT` or `SASL_SSL`. There is no
  default, because a wrong guess fails late and is hard to diagnose.
  `SASL_SSL` uses MSK IAM authentication (`AWS_MSK_IAM` in kafka-python) with
  the runner role's credentials and `AWS_REGION`.
- `topics`: a JSON list of `{name, partitions, configs}`. `partitions`
  defaults to 1. The replication factor is the cluster default.
- `topics_file`: a JSON file with the same list, relative to this project. Put
  it in the step's overlay. Set `topics` or `topics_file`, not both.

## Recommended topics

Copy one of the `*.json.example` files, remove `.example`, and rename the
`schema-history.*` topic to the connector's `schema_history_topic`.

- Schema history: 1 partition, `cleanup.policy=delete`, `retention.ms=-1`,
  `retention.bytes=-1`. Debezium needs one global order of DDL, and a finite
  retention breaks recovery.
- Kafka Connect topics (`connect-offsets`, `connect-configs`,
  `connect-status`): `cleanup.policy=compact`, no finite retention. It is not
  verified if MSK Connect creates them with good settings. Creating them first
  does no harm.

## Runner

Use a runner in the VPC that can reach the brokers. On the deploy-runner
image, add the `cdc` env to `python_envs` so the run needs no internet access.

## Pipeline example

```yaml
- project: cdc-topics-appdb
  source: propeller:cdc-topics
  target: <account>
  runner: <in-vpc runner>
  inputs:
    - name: msk-cluster.bootstrap_brokers_sasl_iam
      var: bootstrap_servers
    - var: security_protocol
      literal: SASL_SSL
    - var: topics_file
      literal: topics.json
```

## Sleep and teardown

- MSK sleep destroys the cluster, and with it the topics and offsets. On wake,
  run this project again before the connector. Debezium then does a recovery
  snapshot.

## Test

```bash
uv run --project platform/shared/python/cdc pytest platform/projects/cdc-topics
```

## References

- [Debezium schema history topic settings](https://debezium.io/blog/2018/03/16/note-on-database-history-topic-configuration/)
- [Kafka Connect in distributed mode](https://kafka.apache.org/documentation/#connect_running)
- [MSK IAM access control](https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html)
