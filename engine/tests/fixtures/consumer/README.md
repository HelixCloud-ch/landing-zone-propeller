# Fixture consumer repo

Input for the engine's resolve and assembly tests. For an illustration of consumer
layout, see `docs/examples/`.

`cases.yaml` records what each project in `platforms/main/pipeline.yaml` exercises,
and every project must have an entry. Those notes appear against each project in
`tests/golden/bundle-report.md`, which is the readable account of how the fixture
assembles.

| Source | Role |
|--------|------|
| `lookup` | data sources only, creates nothing, publishes IDs |
| `store` | stateful, with credentials and a size mapping |
| `store-tuned` | `base: store` plus an overlay |
| `cache` | stateful, one output |
| `service` | justfile only, no terraform |
| `smoke-test` | shares a name with `platform/projects/smoke-test` |
