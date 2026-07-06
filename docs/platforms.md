# Platforms

A platform is the per-workload infrastructure (networking, clusters, databases,
...) deployed into one or more workload accounts created by the landing zone.
Each platform is its own pipeline, deployed independently of the landing zone
and of other platforms, by the same engine and Autopilot Lambda.

Read [concepts](concepts.md) for the landing-zone mental model first; platforms
build on the same pipeline/stage/step/project model.

## How it differs from the landing zone

- The landing zone is one pipeline per consumer repo. Platforms are many, one
  per workload.
- The landing-zone pipeline is framework-defined and customized through
  `propeller.overrides.yaml`. A platform pipeline is consumer-authored: the
  consumer writes the `pipeline.yaml` directly.
- Both draw project sources from the same framework version, defined in the
  `propeller.overrides.yaml` file.

## Repository layout

```
infrastructure/
├── landing-zone/
│   ├── propeller.overrides.yaml
│   └── projects/                   # consumer overlays for landing-zone projects
└── platforms/
    ├── acme-prod/
    │   ├── pipeline.yaml            # consumer-authored
    │   └── projects/                # consumer overlays for platform projects
    │       └── eks-cluster/
    │           └── terraform/
    │               └── config.auto.tfvars
    └── beta-staging/
        ├── pipeline.yaml
        └── projects/
```

Each platform lives under `platforms/<name>/`. Its `pipeline.yaml` composes
framework-shipped platform projects; its `projects/` directory holds optional
per-project overlays (tfvars, Terraform override files), the same overlay
mechanism the landing zone uses.

## Authoring a platform pipeline

A platform `pipeline.yaml` uses the same schema as the landing-zone pipeline
(see [pipeline schema](pipeline-schema.md)). Reference framework platform
projects by name. No `source:` is needed, the engine finds them in the
framework's `platform/projects/`.

```yaml
# platforms/acme-prod/pipeline.yaml
version: "1"
namespace: acme-prod

stages:
  - name: network
    steps:
      - project: vpc
        target: workload-acme-prod
        outputs:
          - name: vpc_id
            var: vpc_id

  - name: compute
    steps:
      - project: eks-cluster
        target: workload-acme-prod
        inputs:
          - name: vpc.vpc_id
            var: vpc_id
```

- `namespace` scopes the platform's SSM keys and state. Use the workload name,
  which should be unique.
- `target` is the workload account the step deploys into (resolved from the
  account registry the landing-zone populates).
- Cross-project inputs/outputs work exactly as in the landing zone.

Consumer-authored projects that don't exist in the framework use an explicit
`source:` pointing at a path under the platform directory, the same as custom
landing-zone projects.

## Configuring projects

Per-project Terraform variables go in an overlay mirroring the project
structure:

```
platforms/acme-prod/projects/eks-cluster/terraform/config.auto.tfvars
```

The assembler merges the overlay onto the framework project at bundle time. See
[project structure](project-structure.md) for the overlay rules.

## Deploying

```bash
just platform-build acme-prod      # resolve + validate + bundle, into dist/acme-prod/
just platform-deploy acme-prod     # build + upload + trigger
just platform-deploy-all           # deploy every platform under platforms/
```

Each platform builds into its own `dist/<name>/` directory and deploys as an
independent Autopilot run. Platforms don't block each other.

`DEPLOY_ACTION=plan just platform-deploy acme-prod` runs a plan instead of an
apply.

`DEPLOY_ACTION=sleep just platform-deploy acme-prod` puts the platform to sleep
(reverse stage order, destroys or stops sleepable resources). Use
`DEPLOY_ACTION=wake` to bring it back. Only steps with `sleep: true` are
affected; all others are skipped. See
[project structure — sleep/wake](project-structure.md#sleep--wake) for details.

## VPC deploy runner

Steps that need private network access (e.g. deploying into a private EKS
cluster with helm/kubernetes providers) can specify `runner:` to use a
VPC-attached CodeBuild project instead of the default deploy-runner. See
[pipeline schema — runner](pipeline-schema.md) and the `deploy-runner-vpc`
platform project.

## See also

- [Pipeline schema](pipeline-schema.md) - the pipeline-side wiring.
- [Project structure](project-structure.md) - project layout and overlays.
- [Customization](customization.md) - the equivalent patterns for the landing
  zone.
- [Glossary](glossary.md) - platform, workload, workload account.
