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
        depends_on: [operations-baseline]
        inputs:
          - name: operations-baseline.log_bucket
            var: log_bucket_arn
        outputs:
          - name: account-factory.admin_role_arn
            var: admin_role_arn
          - name: /accounts.workload-acme.id
            var: workload_account_id
```

## Fields

**Top-level:**
- `version` - schema version (currently `"1"`)
- `namespace` - pipeline identifier, used as prefix for SSM paths, state keys, and other scoped resources
- `stages` - ordered list; stages run sequentially

**Step:**
- `project` - project name (matches `name` in `project.yaml`)
- `target` - logical account to deploy into
- `depends_on` - projects that must complete first (within the same stage)
- `inputs` - values to read from SSM before deploy
- `outputs` - values to write to SSM after deploy

**Input/Output (same fields for both):**
- `name` - SSM path (dots become `/` separators)
- `var` - project-local name (terraform variable or output)

## Path resolution

- No `/` prefix: namespace is prepended automatically.
  `name: identity.admin_role_arn` → `/propeller/landing-zone/identity/admin_role_arn`
- `/` prefix: absolute, no namespace.
  `name: /accounts.workload-acme.id` → `/propeller/accounts/workload-acme/id`

Use absolute paths for shared cross-pipeline values.

## `propeller.overrides.yaml`

```yaml
propeller:
  version: "v1.0.0"
  repo: "HelixCloud-ch/landing-zone-propeller"

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

**`pipeline` section:**
- `targets` - remap project targets to different accounts
- `overrides` - replace project sources with local versions
- `additions` - add steps to stages, or new stages (with `after:`)
- `removals` - remove projects from the pipeline
- `stage_order` - reorder stages
