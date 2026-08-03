# Concepts

A short mental model of how Propeller works. Read this first.

## What it is

Propeller deploys AWS landing zones and platforms across many accounts. A
landing zone has a lot of moving parts (organization, accounts, OUs, Control
Tower, identity, networking) that need to land in the right order and exchange
information as they go (account IDs, role ARNs, OU IDs). Propeller coordinates
all of that.

The framework ships an opinionated default landing zone. Adopters take the
default, customize what they need, and deploy. There is no forking, so adopting
framework improvements is a version bump, not a merge conflict.

## How it's organized

The starting point is a **pipeline** described by one YAML file. A pipeline is a
sequence of **stages**; each stage is a group of **steps**; each step deploys a
**project**.

```
pipeline (propeller.yaml)
└── stage: foundation
    ├── step: control-tower-prerequisites
    ├── step: control-tower
    └── step: ou-infrastructure
└── stage: identity
    └── step: base-sso
```

Stages are barriers by default: all steps in a stage must complete before the
next stage starts. Steps inside a stage run in parallel when they can, in
sequence when one needs another's output.

### Execution groups

Stages can opt out of barrier behavior with `barrier: false`. Consecutive
non-barrier stages merge into an **execution group** where the DAG handles all
ordering based on declared `depends_on` and inferred dependencies. This allows
fine-grained parallelism without flattening the pipeline into a single stage.

```yaml
stages:
  - name: cluster
    barrier: false
    steps:
      - project: eks-cluster-1
        source: propeller:eks-cluster
        target: workload-acc

  - name: data
    barrier: false
    steps:
      - project: rds-oracle-1
        source: propeller:rds-oracle
        target: workload-acc
        depends_on: [eks-cluster-1]

  - name: apps       # barrier: true (default) — waits for cluster+data
    steps:
      - project: my-app
        source: local:my-app
        target: workload-acc
```

Here `cluster` and `data` merge into one execution group. `apps` is a barrier
and waits for the entire group to finish.

### Dependency inference

Beyond explicit `depends_on`, the DAG infers dependencies from input SSM key
paths. If a step reads from `/propeller/{namespace}/{project}`, it implicitly
depends on that project. This keeps pipelines readable without requiring every
dependency to be spelled out.

## Framework and consumer

Propeller has two halves.

The **framework** is this repository. It ships the engine, the default
landing-zone pipeline, all its projects, shared recipes, and the Autopilot
Lambda that orchestrates deployments.

The **consumer** is the user-facing repository. It pins a framework version (in
`.propeller-version`) and holds the customizations: which framework projects to
configure, which to add, which to remove. The consumer never edits or forks the
framework; it overlays on top.

A deploy combines both halves and runs them through the framework's
infrastructure.

## What a deploy does

The consumer's CI builds a deployment artifact (bundle), uploads it to S3, and
invokes the Autopilot Lambda. The Lambda walks the pipeline as a durable
execution, deploys each step into its target account via CodeBuild, and captures
outputs so later steps can use them.

### Deploy modes

- **Autopilot** (default): runs plan and apply back-to-back for each project.
- **Supervised**: every project pauses after plan, waits for approval, then
  applies from the saved plan. Per-project approval is also available via
  `approval: "required"` on individual steps.

### Actions

| Action | Behavior |
|--------|----------|
| `apply` | Plan + apply each project (or saved-plan apply in supervised mode) |
| `plan` | Plan only, no changes applied |
| `destroy` | Reverse stage order, terraform destroy. Requires explicit project list or `destroy_all` flag |
| `sleep` | Reverse stage order, execute sleep recipes for projects in the active preset |
| `wake` | Forward stage order, execute wake recipes using stored per-project modes |

## Sleep presets

Sleep is a cost-optimization mechanism. Instead of per-project opt-in flags,
Propeller uses **presets**: named mappings of project names to sleep modes,
declared at the pipeline level.

```yaml
sleep_presets:
  light:
    rds-oracle-1: stop
  deep:
    rds-oracle-1: snapshot
    eks-cluster-1: destroy
```

A sleep invocation specifies a preset name. Only the projects listed in that
preset participate. Each project implements its modes as `sleep-{mode}` /
`wake-{mode}` recipes in its justfile.

On successful sleep, the preset and per-project modes are stored in SSM. Wake
reads from storage (not from the pipeline YAML), so the wake is deterministic
even if presets are modified between sleep and wake.

## What's next

- Setting up a fresh AWS org: [bootstrap](../bootstrap/README.md).
- Org already bootstrapped: [consumer setup](consumer-setup.md).
- Reference for the schemas: [pipeline-schema](pipeline-schema.md) and
  [project-structure](project-structure.md).
- Deploying platforms: [platforms](platforms.md).
- Terminology: [glossary](glossary.md).
