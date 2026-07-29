# Project structure

How a project lives on disk, what `project.yaml` declares, and how consumer
overlays merge with framework projects at bundle time.

A project is the on-disk source for one deployable unit. It's referenced by name
from a pipeline step, deployed into the step's `target` account, and
reads/writes data through the inputs and outputs declared in the pipeline. See
[pipeline-schema.md](pipeline-schema.md) for the wiring side.

## Layout

Each project lives at `<pipeline>/projects/<project-name>/` and always contains
a `project.yaml` and a `justfile`.

```
platform/projects/rds-oracle/
├── project.yaml
├── justfile
├── README.md
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── providers.tf
    └── versions.tf
```

The justfile is the project's entry point. The Autopilot calls `just plan`,
`just apply`, `just destroy`, `just sleep`, or `just wake` depending on the
deploy action. Most projects import the shared terraform recipe and wire up
the standard actions:

```just
import "../../../shared/recipes/terraform.just"

plan: tf-plan
apply: tf-apply
destroy: tf-destroy
```

The shared recipe handles init, backend configuration, variable injection (via
`_propeller-vars`), output extraction, and plan storage for supervised mode.

## `project.yaml`

The project's self-description. Keep this minimal. All wiring (target, inputs,
outputs, dependencies) lives in the pipeline step, not here.

```yaml
name: rds-oracle
description: >-
  Deploys an RDS Oracle instance with managed credentials.

metadata:
  cost-center: platform

deploy:
  type: just
```

### Fields

- `name` - unique identifier within the pipeline. Must match the folder name.
- `description` - human-readable summary.
- `metadata.cost-center` - optional, becomes the `propeller:cost-center` tag.
- `metadata.framework-required` - optional, set to `true` for framework-only
  resources (Lambda, CodeBuild runners, etc.).
- `deploy.type` - always `just` for new projects.

## Shared terraform recipe

The framework ships `shared/recipes/terraform.just` which provides:

- `tf-init` - backend configuration from env vars
- `tf-plan` - plan with variable injection, plan storage for supervised mode
- `tf-apply` - apply (from saved plan in supervised mode, or fresh)
- `tf-destroy` - destroy with variable injection
- `_propeller-vars` - writes all `PROPELLER_INPUT_*` env vars and tags to
  `_propeller.auto.tfvars.json` using jq
- `_propeller-outputs` - extracts terraform outputs to
  `.propeller-outputs.json`

### Plan storage

When `PROPELLER_EXECUTION_ID` is set (always in production), the plan binary is
saved to S3 (`propeller-plans/{execution_id}/{project}.tfplan`). In supervised
mode, the apply phase retrieves and applies this exact plan.

If `PROPELLER_PLAN_BUCKET` is set, a JSON representation of the plan is also
stored for UI/review consumption.

### Sleep and wake

The shared recipe provides mode-aware sleep/wake dispatch:

```just
sleep:
    just sleep-{{ _sleep_mode }}

wake:
    just wake-{{ _sleep_mode }}
```

`PROPELLER_SLEEP_MODE` is set by the Autopilot based on the active preset.
The shared recipe also provides `sleep-destroy` / `wake-destroy` as built-in
modes. Projects add custom modes by defining additional recipes.

### Sleep state helpers

For modes that need to pass data between sleep and wake (beyond deterministic
naming), the shared recipe provides:

```just
_sleep-state-write data    # writes JSON to s3://{state_bucket}/{sleep_state_key}
_sleep-state-read          # reads it back (returns {} if missing)
```

## Implementing sleep modes

Projects declare which modes they support by adding `sleep-{mode}` and
`wake-{mode}` recipes to their justfile. The pipeline's `sleep_presets`
determines which mode is used at runtime.

Example (RDS Oracle with stop and snapshot modes):

```just
import "../../../shared/recipes/terraform.just"

plan: tf-plan
apply: tf-apply
destroy: tf-destroy

# Default mode when no preset specifies otherwise
sleep-default: sleep-stop
wake-default: wake-stop

sleep-stop: tf-init
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ _tf_dir }}
    DB_ID=$(terraform output -raw db_instance_identifier)
    aws rds stop-db-instance --db-instance-identifier "$DB_ID" --region "$AWS_REGION"

wake-stop: tf-init
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ _tf_dir }}
    DB_ID=$(terraform output -raw db_instance_identifier)
    aws rds start-db-instance --db-instance-identifier "$DB_ID" --region "$AWS_REGION"
    aws rds wait db-instance-available --db-instance-identifier "$DB_ID" --region "$AWS_REGION"

sleep-snapshot: tf-init
    # Targeted destroy with final snapshot (preserves SG, subnet group, secrets)
    ...

wake-snapshot: tf-init
    # Restore from deterministic snapshot ID, then clean up snapshot
    ...
```

Common sleep modes:

| Mode | On sleep | On wake | Use case |
|------|----------|---------|----------|
| `destroy` | `terraform destroy` | `terraform apply` | Clusters, NAT gateways |
| `stop` | API stop call | API start + wait | RDS, Aurora |
| `snapshot` | Targeted destroy with final snapshot | Apply with snapshot_identifier | RDS (long sleep, avoid 7-day restart) |

The deterministic snapshot ID convention is `propeller-sleep-{PROJECT_NAME}`
(available as `{{ _sleep_snapshot_id }}` in the justfile). This avoids needing
state files to reconnect sleep and wake.

## Environment variables

The Autopilot sets these env vars in CodeBuild for every project:

| Variable | Description |
|----------|-------------|
| `PROJECT_NAME` | Project name |
| `PROPELLER_NAMESPACE` | Pipeline namespace |
| `AWS_ACCOUNT_ID` | Target account ID |
| `AWS_REGION` | Deploy region |
| `DEPLOY_ACTION` | Current action (apply, plan, etc.) |
| `PROPELLER_EXECUTION_ID` | Durable execution ID |
| `PROPELLER_INPUT_*` | Resolved input values |
| `PROPELLER_FRAMEWORK_TAGS_JSON` | Framework tags (JSON object) |
| `PROPELLER_CONSUMER_TAGS_JSON` | Consumer tags (JSON object) |
| `PROPELLER_SLEEP_MODE` | Sleep mode for this project (sleep/wake only) |
| `PROPELLER_SAVED_PLAN` | Set to "1" in supervised apply phase |
| `PROPELLER_PLAN_BUCKET` | Centralized plan bucket (if configured) |

## Tags

The framework injects tags on every resource. Terraform projects expose three
variables that the shared recipe wires automatically:

```hcl
variable "tags"           { type = map(string)  default = {} }
variable "consumer_tags"  { type = map(string)  default = {} }
variable "propeller_tags" { type = map(string)  default = {} }
```

Precedence (lowest to highest): `consumer_tags` < `tags` < `propeller_tags`.

Framework tags emitted per project:

- `propeller:pipeline` - namespace
- `propeller:project` - project name
- `propeller:deploy-type` - deploy type
- `propeller:cost-center` - from `metadata.cost-center` (when set)
- `propeller:framework-required` - from `metadata.framework-required` (when true)

## Consumer overlays

Consumers customize framework projects by mirroring the project structure and
dropping in overlay files:

```
platforms/acme-prod/projects/rds-oracle-1/
└── terraform/
    └── config.auto.tfvars
```

Recognized overlay files:

- `*.auto.tfvars` - Terraform variable values, auto-loaded at plan/apply time.
- Terraform
  [override files](https://developer.hashicorp.com/terraform/language/files/override) -
  merged on top of same-named blocks.

The bundle assembler copies the framework project first, then overlays consumer
files on top. Consumer files win on conflict.

### Custom (consumer-only) projects

Consumers can add projects that don't exist in the framework. Same structure,
just provide the full project source:

```
platforms/acme-prod/projects/my-custom-app/
├── project.yaml
├── justfile
└── terraform/
    ├── main.tf
    └── variables.tf
```

Reference it from the pipeline with an explicit `source:` path:

```yaml
- project: my-custom-app
  source: "./platforms/acme-prod/projects/my-custom-app"
  target: workload-acc
```

## Multi-instance projects

Deploy the same framework project multiple times with different names:

```yaml
- project: oracle-app1
  source: rds-oracle
  target: workload-acc

- project: oracle-app2
  source: rds-oracle
  target: workload-acc
```

Each gets separate Terraform state, separate overlay dir, separate SSM outputs.
The `source` field resolves by name from the framework project index.

## See also

- [Pipeline schema](pipeline-schema.md) - pipeline-side wiring (target, inputs,
  outputs, dependencies).
- [Platforms](platforms.md) - authoring platform pipelines.
- [Customization](customization.md) - adding, removing, overriding projects.
- [Glossary](glossary.md) - canonical terminology.
