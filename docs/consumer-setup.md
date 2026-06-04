# Consumer setup

A walkthrough from zero to a configured, ready-to-deploy consumer repo. Read
[concepts](concepts.md) first for the mental model.

This guide assumes the framework prerequisites have been bootstrapped. If not,
follow [bootstrap](../bootstrap/README.md) first.

The deploy itself is covered in [CI setup](ci-setup.md). Getting the
configuration right is the bulk of the work.

## Local tools

CI installs everything it needs on each run, so deploying via GitHub Actions
will have no local prerequisites. The tools below are required only when running
`just pull` or other commands locally, and are useful for day-to-day work on the
consumer repo.

- [just](https://just.systems/) - command runner
- [uv](https://docs.astral.sh/uv/) - Python package manager
- [yq](https://github.com/mikefarah/yq) - YAML query tool
- [jq](https://jqlang.github.io/jq/) - JSON query tool
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) -
  AWS command-line interface
- `curl`, `unzip`

No local AWS credentials are required. Plan and apply both run through CI
against the Autopilot Lambda; the consumer repo never needs to talk to AWS from
a developer machine.

## 1. Initialize a consumer repo

In an empty git repository, run:

```bash
curl -fsSL https://raw.githubusercontent.com/HelixCloud-ch/landing-zone-propeller/main/consumer/init.sh | bash
```

To pin a specific framework version:

```bash
curl -fsSL https://raw.githubusercontent.com/HelixCloud-ch/landing-zone-propeller/main/consumer/init.sh | bash -s -- --version v1.0.0
```

This scaffolds the consumer repo with a `justfile` (importing recipes from the
framework), a `landing-zone/propeller.overrides.yaml` (framework version and
customizations), `landing-zone/projects/` populated with starter
`config.auto.tfvars` overlays for each framework project that needs
configuration, and a `.gitignore` that excludes the cached framework checkout.

The starter overlays list each project's required and commonly-set variables
with placeholder values and short comments. The repo is a few placeholders away
from a valid deploy.

Commit the result.

## 2. Pull the framework

```bash
just pull
```

This downloads the framework at the version pinned in
`landing-zone/propeller.overrides.yaml`. After this, `.propeller/` exists and
contains the engine, the consumer recipes, and the framework's project sources.
The directory is gitignored and refreshed by every `just pull` - treat it as
read-only, useful for inspection and debugging only.

## 3. Review what the framework deploys

Run `just resolve` to produce a Mermaid graph of the resolved pipeline at
`dist/landing-zone/pipeline.lock.md`. Open it in any Markdown previewer (VS
Code, GitHub, etc.) for a visual map of stages, steps, and dependencies.

For deeper detail on individual projects, read each project's README under
`.propeller/landing-zone/projects/<name>/README.md`.

Some of the decisions to make at this point:

- **AWS region** for Control Tower's home region. Cannot be changed later
  without rebuilding the landing zone.
- **Email addresses** for the governance accounts (log archive, audit, optional
  backup). Each must be unique and not previously used in any AWS account.
- **OU names** if the defaults don't match local conventions.
- **Optional features to enable.**
- **Tags** for cost attribution and ownership.

These go into the override files in the next step.

## 4. Configure the pipeline

Two places hold configuration.

**`landing-zone/propeller.overrides.yaml`** controls pipeline-level choices:
which framework version to use, target remappings, projects to add or remove,
and stage ordering. The init script generates this file with examples commented
out. See [customization](customization.md) for the full set of options.

**`landing-zone/projects/<project-name>/terraform/config.auto.tfvars`** holds
per-project Terraform variables. The init script generates a starter overlay for
each framework project that needs configuration, listing the required and
commonly-set variables with placeholder values. Edit the placeholders to your
real values; the assembler merges the overlay into the bundle at deploy time.
For example, configuring Control Tower prerequisites:

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

Refer to the framework project's `variables.tf` and `README.md` for the full
list of configurable inputs. See [project structure](project-structure.md) for
the overlay rules.

## What this step produces

- A consumer repo with `propeller.overrides.yaml` and any project overlays
  needed
- Configuration decisions (region, account emails, OU names, tags) committed to
  the repo

## What's next

Run a plan from CI to validate the configuration before any apply. The next step
wires up GitHub Actions:

- [CI setup](ci-setup.md) - configure the deploy workflow.

Other useful destinations once CI is running:

- [Customization](customization.md) - extend the pipeline with custom projects,
  additional stages, or removed defaults.

Common reference docs: [pipeline schema](pipeline-schema.md),
[project structure](project-structure.md).
