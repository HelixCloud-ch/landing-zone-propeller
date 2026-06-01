# Propeller Engine

CLI tooling for resolving, validating, and bundling propeller pipelines.

## Setup

Requires Python 3.12+ and [uv](https://docs.astral.sh/uv/).

```bash
uv sync --project engine
```

## Commands

### propeller-resolve

Merges a base pipeline with overrides to produce a resolved lock file and a
Mermaid pipeline graph.

```bash
uv run --project engine propeller-resolve \
    --base landing-zone/propeller.yaml \
    --overrides landing-zone/propeller.overrides.yaml \
    --output dist/pipeline.lock.yaml \
    --propeller-dir landing-zone
```

Outputs:

- `dist/pipeline.lock.yaml` - resolved pipeline with sources, targets, inputs,
  outputs
- `dist/pipeline.lock.md` - Mermaid graph for visual inspection

### propeller-validate

Checks a resolved pipeline for correctness (duplicates, dependency graph, source
paths). Use `--no-check-sources` to skip filesystem checks.

```bash
uv run --project engine propeller-validate \
    --pipeline dist/pipeline.lock.yaml
```

### propeller-bundle

Assembles a self-contained deployment zip from the resolved pipeline.

```bash
uv run --project engine propeller-bundle \
    --pipeline dist/pipeline.lock.yaml \
    --propeller-dir landing-zone \
    --output dist/bundle.zip
```

The bundle is a self-contained zip with projects, shared modules, the engine,
and a `MANIFEST.yaml`.

### propeller-deploy

Runs inside CodeBuild to deploy a single project. Reads `project.yaml`, injects
`PROPELLER_INPUT_*` env vars as Terraform variables (or runner-specific
parameters), and writes outputs to `.propeller-outputs.json`.

```bash
propeller-deploy --project-dir /tmp/bundle/projects/example-terraform init
propeller-deploy --project-dir /tmp/bundle/projects/example-terraform apply
```

Subcommands: `init`, `plan`, `apply`, `destroy`, `outputs`. Works with
Terraform, CloudFormation, and script projects via `deploy.type` in
`project.yaml`.

## Reference

- Pipeline schema: [`docs/pipeline-schema.md`](../docs/pipeline-schema.md)
- Project structure: [`docs/project-structure.md`](../docs/project-structure.md)
- Working examples: [`docs/examples/`](../docs/examples/)
