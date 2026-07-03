# Pipeline Schema

## `propeller.yaml`

```yaml
version: "1"
namespace: landing-zone

stages:
  - name: baseline
    steps:
      - project: operations-baseline
        target: operations
        outputs:
          - name: operations-baseline.log_bucket
            var: log_bucket

      - project: security-hub
        target: management
        outputs:
          - name: security-hub.findings_arn
            var: findings_arn

  - name: identity
    steps:
      - project: account-factory
        target: management
        timeout: 90
        depends_on: [operations-baseline]
        inputs:
          - name: operations-baseline.log_bucket
            var: log_bucket
        outputs:
          - name: account-factory.admin_role_arn
            var: admin_role_arn
          - name: /accounts.workload-acme.id
            var: workload_account_id
```

## Fields

**Top-level:**

- `version` - schema version (currently `"1"`)
- `namespace` - pipeline identifier, used as prefix for SSM paths, state keys,
  and other scoped resources
- `stages` - ordered list; stages run sequentially

**Step:**

- `project` - project name (matches `name` in `project.yaml`)
- `target` - logical account to deploy into
- `depends_on` - projects that must complete first (within the same stage)
- `timeout` - CodeBuild timeout override in minutes (default: CodeBuild project
  setting, typically 60). Use for long-running steps like cluster provisioning.
- `runner` - CodeBuild project name to use for this step (default:
  `deploy-runner`). Set to the name of a VPC-attached CodeBuild project when the
  step needs private network access (e.g. deploying into a private EKS cluster).
- `inputs` - values to read from SSM before deploy
- `outputs` - values to write to SSM after deploy

**Input/Output (same fields for both):**

- `name` - SSM path (dots become `/` separators)
- `var` - project-local name (terraform variable or output). Defaults to `name`
  if omitted.

## Path resolution

Outputs:

- Bare name (no `/` prefix): stored as a field in the project's JSON blob
  parameter. `name: org_id` → field `org_id` in
  `/propeller/landing-zone/control-tower-prerequisites`
- `/` prefix: stored as an individual plain-string parameter.
  `name: /accounts.workload-acme.id` → `/propeller/accounts/workload-acme/id`

Inputs:

- `project.field` format: reads from the project's JSON blob.
  `name: control-tower-prerequisites.org_id` → reads field `org_id` from
  `/propeller/landing-zone/control-tower-prerequisites`
- `/` prefix: reads an individual parameter. `name: /accounts.workload-acme.id`
  → `/propeller/accounts/workload-acme/id`
- `@namespace/project.field` format: reads from another pipeline's project blob.
  `name: @landing-zone/workload-parameters.tgw_id` → reads field `tgw_id` from
  `/propeller/landing-zone/workload-parameters`. Use this for cross-pipeline
  references (e.g. a platform pipeline consuming landing-zone outputs).

Use absolute paths (`/`) for shared values that should be individually readable
(e.g. account IDs). Adopt a sound naming strategy for these paths.

## `propeller.overrides.yaml`

```yaml
propeller:
  version: "v1.0.0"
  repo: "HelixCloud-ch/landing-zone-propeller"

# Pipeline-wide tags applied via provider default_tags on every project
tags:
  "acme:cost-center": "platform"
  "acme:environment": "dev"

pipeline:
  # Remap targets
  targets:
    operations-baseline: sandbox

  # Use a local project source instead of the framework's
  overrides:
    - project: identity
      source: "./landing-zone/projects/custom-identity"

  # Add a step to an existing stage
  additions:
    - stage: baseline
      step:
        project: custom-logging
        source: "./landing-zone/projects/custom-logging"
        target: operations
        outputs:
          - name: custom-logging.endpoint
            var: endpoint

  # Insert a new stage after an existing one
  additions:
    - stage: governance
      after: baseline
      steps:
        - project: scp-baseline
          source: "./landing-zone/projects/scp-baseline"
          target: management

  # Remove a project
  removals:
    - project: security-hub

  # Reorder stages (must list all)
  stage_order:
    - identity
    - baseline
```

**`propeller` section:**

- `version` - framework version to pull
- `repo` - GitHub repo (default: `HelixCloud-ch/landing-zone-propeller`)

**`tags` section:**

- map of tags applied to every project's resources via provider `default_tags`.
  Per-project tags (in tfvars) override these; framework `propeller:*` tags
  override both.

**`pipeline` section:**

- `targets` - remap project targets to different accounts
- `overrides` - replace project sources with local versions
- `additions` - add steps to stages, or new stages (with `after:`)
- `removals` - remove projects from the pipeline
- `stage_order` - reorder stages

## Framework tags

The engine reads each project's `project.yaml` and emits a small set of tags on
every resource. See [project-structure.md](project-structure.md#tags) for the
full list and merge rules.
