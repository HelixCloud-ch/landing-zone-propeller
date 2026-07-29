# Consumer setup

A walkthrough from zero to a configured, ready-to-deploy consumer repo. Read
[concepts](concepts.md) first for the mental model.

This guide assumes the framework prerequisites have been bootstrapped. If not,
follow [bootstrap](../bootstrap/README.md) first.

The deploy itself is covered in [CI setup](ci-setup.md). Getting the
configuration right is the bulk of the work.

## Local tools

CI installs everything it needs on each run. The tools below are only required
for running `just pull` or local validation.

- [just](https://just.systems/) - command runner
- [uv](https://docs.astral.sh/uv/) - Python package manager (runs the engine)
- [yq](https://github.com/mikefarah/yq) - YAML query tool
- [jq](https://jqlang.github.io/jq/) - JSON query tool
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- `curl`, `unzip`

No local AWS credentials are needed. Plan and apply both run through CI against
the Autopilot Lambda.

## 1. Initialize a consumer repo

In an empty git repository, run:

```bash
curl -fsSL https://raw.githubusercontent.com/HelixCloud-ch/landing-zone-propeller/main/consumer/init.sh | bash
```

To pin a specific framework version:

```bash
curl -fsSL https://raw.githubusercontent.com/HelixCloud-ch/landing-zone-propeller/main/consumer/init.sh | bash -s -- --version v1.0.0
```

This scaffolds the consumer repo with:

- `.propeller-version` pinning the framework version
- `justfile` importing recipes from the framework
- `landing-zone/propeller.overrides.yaml` for pipeline customizations
- `landing-zone/projects/` with starter `config.auto.tfvars` overlays
- `.gitignore` excluding the cached framework checkout

Commit the result.

## 2. Pull the framework

```bash
just pull
```

Downloads the framework at the version in `.propeller-version`. After this,
`.propeller/` exists and contains the engine, the consumer recipes, and the
framework's project sources. The directory is gitignored and refreshed by every
`just pull`. Treat it as read-only.

## 3. Review what the framework deploys

```bash
just resolve
```

Produces a Mermaid graph at `dist/landing-zone/pipeline.lock.md`. Open it in any
Markdown previewer for a visual map of stages, steps, and dependencies.

Decisions to make at this point:

- **AWS region** for Control Tower's home region (cannot change later).
- **Email addresses** for governance accounts (log archive, audit). Each must be
  unique and not previously used in any AWS account.
- **OU names** if defaults don't fit.
- **Tags** for cost attribution.

## 4. Configure the pipeline

Two places hold configuration.

### Version pin

**`.propeller-version`** contains the framework version tag (e.g. `v2.1.0`).
Update this file to upgrade.

```
v2.1.0
```

### Pipeline customization

**`landing-zone/propeller.overrides.yaml`** controls pipeline-level choices:
target remappings, projects to add or remove, stage ordering, and consumer tags.
See [customization](customization.md) for the full set of options.

```yaml
# Example: remap and tag
tags:
  "acme:environment": "prod"

pipeline:
  targets:
    operations-baseline: my-ops-account
```

### Direct pipeline mode

For consumers that don't use the framework's default landing-zone pipeline
(e.g. they already have a landing zone and only need a few specific projects),
place a `landing-zone/propeller.yaml` directly. The engine uses it as-is,
skipping the base+overrides merge.

### Per-project configuration

**`landing-zone/projects/<project-name>/terraform/config.auto.tfvars`** holds
per-project Terraform variables.

```
landing-zone/
└── projects/
    └── control-tower-prerequisites/
        └── terraform/
            └── config.auto.tfvars
```

```hcl
region                      = "eu-central-2"
log_archive_account_email   = "aws+log-archive@example.com"
audit_account_email         = "aws+audit@example.com"
```

Refer to the framework project's `variables.tf` and `README.md` for available
inputs. See [project structure](project-structure.md) for the overlay rules.

## What this step produces

- A consumer repo with `.propeller-version`, optional `propeller.overrides.yaml`,
  and project overlays
- Configuration decisions committed

## What's next

- [CI setup](ci-setup.md) - wire up GitHub Actions for plan/apply.
- [Platforms](platforms.md) - deploy workload infrastructure.
- [Customization](customization.md) - extend or modify the pipeline.

Reference: [pipeline schema](pipeline-schema.md),
[project structure](project-structure.md).
