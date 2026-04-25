# Propeller Engine

CLI tooling for resolving, validating, and bundling propeller pipelines.

## Setup

Requires Python 3.12+ and [uv](https://docs.astral.sh/uv/).

```bash
uv sync --project engine
```

## Commands

### propeller-resolve

Merges the base `pipeline.yaml` with overrides to produce a resolved lock file
and a Mermaid pipeline graph.

```bash
uv run --project engine propeller-resolve \
    --base pipeline.yaml \
    --overrides propeller.yaml \
    --output dist/pipeline.lock.yaml \
    --propeller-dir .propeller
```

Outputs:

- `dist/pipeline.lock.yaml` — resolved pipeline with sources, targets, inputs,
  outputs
- `dist/pipeline.lock.md` — Mermaid graph for visual inspection

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
    --propeller-dir .propeller \
    --config-dir config \
    --output dist/bundle.zip
```

The bundle is a self-contained zip with projects, shared modules, config, the
engine, and a `MANIFEST.yaml`.

### propeller-deploy

Runs inside CodeBuild to deploy a single project. Reads `project.yaml`, injects
`PROPELLER_INPUT_*` env vars as terraform variables, and writes outputs to
`.propeller-outputs.json`.

```bash
propeller-deploy --project-dir /tmp/bundle/projects/networking --config /tmp/bundle/config/networking.tfvars init
propeller-deploy --project-dir /tmp/bundle/projects/networking --config /tmp/bundle/config/networking.tfvars apply
```

Subcommands: `init`, `plan`, `apply`, `destroy`, `outputs`. Works with
Terraform, CloudFormation, and script projects via `deploy.type` in
`project.yaml`.

## Pipeline Model

Stages are sequential barriers. Steps within a stage run in parallel unless
constrained by `depends_on`. Cross-stage ordering is implicit from the stage
sequence.

```yaml
version: "1"

stages:
  - name: operations
    steps:
      - project: hello-operations
      - project: hello-operations-2
        depends_on: [hello-operations]

  - name: management
    steps:
      - project: hello-management
```

## Project Contract (`project.yaml`)

Each project declares its deploy type, target account, inputs, and outputs:

```yaml
name: hello-operations-2
target: operations

deploy:
  type: terraform
  backend:
    bucket: "terraform-state-${AWS_ACCOUNT_ID}"
    key: "propeller/hello-operations-2/terraform.tfstate"
    region: "${AWS_REGION}"

inputs:
  - key: /propeller/hello-operations/message
    var: operations_message

outputs:
  - key: /propeller/hello-operations-2/message
    ref: message
```

## Overrides (`propeller.yaml`)

Consumers pin a framework version and customize the pipeline:

```yaml
propeller:
  version: "v1.0.0"

pipeline:
  targets:
    hello-operations: sandbox # override target account

  overrides:
    - project: hello-operations
      source: "./projects/custom-ops"

  additions:
    - stage: operations
      step:
        project: custom-project
        source: "./projects/custom-project"
        depends_on: [hello-operations]

  removals:
    - project: hello-management

  stage_order:
    - management
    - operations
```
