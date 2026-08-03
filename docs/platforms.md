# Platforms

A platform is the per-workload infrastructure (networking, clusters, databases)
deployed into one or more workload accounts. Each platform is its own pipeline,
deployed independently of the landing zone and of other platforms, by the same
engine and Autopilot Lambda.

Read [concepts](concepts.md) for the mental model first; platforms use the same
pipeline/stage/step/project structure.

## How it differs from the landing zone

- The landing zone is one pipeline per consumer repo. Platforms are many, one
  per workload.
- The landing-zone pipeline is framework-defined and customized through
  `propeller.overrides.yaml` (or a direct `propeller.yaml`). A platform
  pipeline is consumer-authored from scratch.
- Both draw project sources from the same framework version pinned in
  `.propeller-version`.

## Repository layout

```
my-consumer/
├── .propeller-version
├── landing-zone/
│   ├── propeller.overrides.yaml
│   └── projects/
└── platforms/
    ├── acme-prod/
    │   ├── pipeline.yaml
    │   └── projects/
    │       └── rds-oracle-1/
    │           └── terraform/
    │               └── config.auto.tfvars
    └── staging/
        ├── pipeline.yaml
        └── projects/
```

Each platform lives under `platforms/<name>/`. Its `pipeline.yaml` composes
framework and custom projects; its `projects/` directory holds per-project
overlays.

## Authoring a platform pipeline

A platform `pipeline.yaml` uses the same schema as the landing-zone pipeline
(see [pipeline schema](pipeline-schema.md)).

```yaml
version: "1"
namespace: acme-prod

stages:
  - name: network
    steps:
      - project: workload-vpc
        source: propeller:workload-vpc
        target: workload-acme-prod
        outputs:
          - name: vpc_id
          - name: subnet_ids_by_tier

  - name: compute
    steps:
      - project: eks-cluster-1
        source: propeller:eks-cluster
        target: workload-acme-prod
        inputs:
          - name: workload-vpc.vpc_id
            var: vpc_id
```

- `namespace` scopes SSM keys and state. Must be unique across all pipelines.
- `target` is the workload account (resolved from the account registry).
- `source` references a framework project by name when `project` differs
  (multi-instance pattern).
- Cross-pipeline inputs use the `@namespace/project.field` syntax.

### Barriers and execution groups

By default every stage is a barrier. For pipelines where stages are mostly
organizational and you want the DAG to handle ordering:

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

  - name: apps
    steps:
      - project: my-app
        source: local:my-app
        target: workload-acc
        depends_on: [eks-cluster-1, rds-oracle-1]
```

`cluster` and `data` merge into one execution group. `apps` waits for the
group to complete.

### Sleep presets

Declare how the platform sleeps:

```yaml
sleep_presets:
  light:
    rds-oracle-1: stop
  deep:
    rds-oracle-1: snapshot
    eks-cluster-1: destroy
```

Projects not listed in a preset are untouched during sleep/wake. See
[project structure](project-structure.md) for implementing sleep modes in
project justfiles.

### Supervised mode and approval

For production platforms, use supervised mode (plan all, then approve, then
apply all from saved plans):

```bash
DEPLOY_MODE=supervised DEPLOY_ACTION=apply just platform-deploy acme-prod
```

Or mark individual high-risk projects for approval even in autopilot mode:

```yaml
- project: eks-cluster-1
  source: propeller:eks-cluster
  target: workload-acc
  approval: "required"
```

## Configuring projects

Per-project Terraform variables go in an overlay:

```
platforms/acme-prod/projects/rds-oracle-1/terraform/config.auto.tfvars
```

The assembler merges the overlay onto the framework project at bundle time. A
platform pipeline is yours, so it has to say where its overlays live. One line at
the top level covers every step:

```yaml
version: "1"
namespace: acme-prod

overlays:
  - projects/${project}
```

See [project structure](project-structure.md) for overlay rules.

## Deploying

```bash
just platform-build acme-prod      # resolve + validate + bundle
just platform-deploy acme-prod     # build + upload + trigger
just platform-deploy-all           # deploy every platform under platforms/
```

Each platform builds into `dist/<name>/` and deploys as an independent Autopilot
execution. Platforms don't block each other.

### Actions

```bash
DEPLOY_ACTION=plan just platform-deploy acme-prod         # plan only
DEPLOY_ACTION=apply just platform-deploy acme-prod        # apply (default)
DEPLOY_ACTION=destroy ONLY=my-project just platform-deploy acme-prod  # destroy one project
```

### Sleep and wake

```bash
DEPLOY_ACTION=sleep SLEEP_PRESET=light just platform-deploy acme-prod
DEPLOY_ACTION=wake just platform-deploy acme-prod   # uses stored preset
```

Sleep reverses stage order and executes the sleep recipe for each project in the
preset. Wake runs forward using the modes stored from the last sleep (so it's
deterministic even if the pipeline YAML changed).

A pipeline in sleeping state blocks normal apply unless `force: true` is passed.

### Targeting a single project

```bash
ONLY=rds-oracle-1 just platform-deploy acme-prod
```

Filters the pipeline to just that project. Works with any action.

## Concurrent execution guard

The Autopilot rejects a new full-pipeline execution if the same namespace
already has one running. Single-project runs (with `ONLY`) bypass this check.

## VPC deploy runner

Steps that need private network access (e.g. deploying into a private EKS
cluster) can specify `runner:` to use a VPC-attached CodeBuild project:

```yaml
- project: eks-addons
  target: workload-acc
  runner: deploy-runner-vpc
```

## See also

- [Pipeline schema](pipeline-schema.md) - full field reference.
- [Project structure](project-structure.md) - project layout, sleep modes, overlays.
- [CI setup](ci-setup.md) - wiring GitHub Actions.
- [Glossary](glossary.md) - platform, workload, workload account.
