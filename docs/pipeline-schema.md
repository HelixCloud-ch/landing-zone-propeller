# Pipeline Schema

## `propeller.yaml`

```yaml
version: "1"
namespace: landing-zone

stages:
  - name: baseline
    steps:
      - project: operations-baseline
        source: propeller:operations-baseline
        target: operations
        outputs:
          - name: operations-baseline.log_bucket
            var: log_bucket

      - project: security-hub
        source: propeller:security-hub
        target: management
        outputs:
          - name: security-hub.findings_arn
            var: findings_arn

  - name: identity
    steps:
      - project: account-factory
        source: propeller:account-factory
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
- `stages` - ordered list; stages run sequentially (unless `barrier: false`)
- `overlays` - (optional) list of default overlay patterns for every step; a step
  declaring its own replaces these. See [Overlays](#overlays)
- `sleep_presets` - (optional) named presets for sleep/wake. Each preset maps
  project names to sleep modes. Example:
  ```yaml
  sleep_presets:
    light:
      rds-oracle-1: stop
    deep:
      rds-oracle-1: snapshot
      eks-cluster-1: destroy
  ```

**Stage:**

- `name` - stage identifier
- `steps` - list of steps in this stage
- `barrier` - (optional, default `true`) when false, this stage merges with
  adjacent non-barrier stages into a single execution group. The DAG handles
  ordering across merged stages.

**Step:**

- `project` - the deployed instance name. Becomes the terraform state key, the SSM
  output path, the overlay directory name and `PROJECT_NAME`, so it is permanent
  identity: renaming one is a data migration, not a rename.
- `source` - which project to deploy, always namespaced. See
  [Source references](#source-references).
- `overlays` - (optional) one path pattern, or a list applied in order, layered
  over the source. See [Overlays](#overlays).
- `target` - logical account to deploy into
- `depends_on` - projects that must complete first (within the same execution
  group, or guaranteed by stage barriers for cross-stage references)
- `timeout` - CodeBuild timeout override in minutes (default: CodeBuild project
  setting, typically 60). Use for long-running steps like cluster provisioning.
- `runner` - CodeBuild project name to use for this step (default:
  `deploy-runner`). Set to the name of a VPC-attached CodeBuild project when the
  step needs private network access (e.g. deploying into a private EKS cluster).
- `approval` - (optional) set to `"required"` to pause this project for manual
  approval after plan, even in autopilot mode.
- `inputs` - values read from SSM, or literals, passed to the deploy
- `outputs` - values to write to SSM after deploy

**Input/Output (same fields for both):**

- `name` - SSM path (dots become `/` separators)
- `var` - project-local name (terraform variable or output). Defaults to `name`
  if omitted.

**Input only:**

- `literal` - a fixed value, used instead of reading a parameter. Mutually
  exclusive with `name`. It travels inside the bundle in cleartext, so it must
  not hold anything secret.

```yaml
inputs:
  - name: eks-cluster.cluster_name    # read from another project's outputs
    var: cluster_name
  - var: chart_version                # fixed value, no parameter read
    literal: "2.4.0"
```

A literal is substituted when the pipeline is resolved, so it is written into the
lock file and travels inside the bundle. Use it for versions, identifiers, sizes
and hostnames. Never for a secret: the bundle is a zip in S3, not a secret store.

## Source references

Every `source` names the namespace it comes from. There is no bare form, so a
reference cannot mean different things depending on how the CLI was invoked.

| Form | Resolves to |
|------|-------------|
| `local:NAME` | a project in the consumer repo |
| `propeller:NAME` | a framework project, by name |
| `propeller://PATH` | deprecated: a path from the framework root |

```yaml
steps:
  - project: cluster
    source: propeller:eks-cluster
  - project: reporting-db
    source: local:org-postgres
```

`local:` searches the directories listed in `sources:` in
`propeller.overrides.yaml`, in order, then the `projects/` directory beside the
pipeline file:

```yaml
sources:
  - shared-projects/
```

`propeller:` takes a project name, not a path. Framework project names are unique
across `landing-zone/` and `platform/`, and a project at the framework root is
included, so one name means one project everywhere. Resolution fails with the list
of known names if there is no match.

Omitting `source`, or writing a name with no namespace, is an error.

## Overlays

An overlay is a directory of files copied over a project after its source,
letting a consumer change part of a project without forking it. Terraform
`*.auto.tfvars` load in filename order, so `config.auto.tfvars` in the source and
`override.auto.tfvars` in an overlay gives the overlay precedence.

```yaml
- project: reporting-db
  source: local:org-postgres
  overlays:
    - org-overlays/${project}
    - overlays/${project}
```

`${project}` expands to the step's project name. Patterns are resolved when the
pipeline is resolved, and one naming a directory that does not exist is skipped:
a pattern describes where an overlay would live, not a promise that one does.
Later entries overwrite earlier ones.

`overlays` at the top level of a pipeline is the default for every step, and a
step declaring its own replaces it. This is how a pipeline states where its
projects may be overlaid without repeating the pattern on each step, which
matters for a pipeline whose consumers customize it through
`propeller.overrides.yaml` and so cannot edit its steps:

```yaml
version: "1"
namespace: landing-zone

overlays:
  - projects/${project}
```

Relative patterns resolve against the directory holding
`propeller.overrides.yaml`, so the pipeline above reads overlays from
`landing-zone/projects/<project>` in the consumer repo.

A step with no overlays, declared or inherited, gets none. `--overlay-dir` does
not select overlays; it names a root to check for directories no step applies,
reported as a warning. Bundling fails if that root holds directories and the
pipeline declares no overlays at all, since every one of them would be ignored.

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
      source: local:custom-identity

  # Add a step to an existing stage
  additions:
    - stage: baseline
      step:
        project: custom-logging
        source: local:custom-logging
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
          source: local:scp-baseline
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

## Lambda event fields

The Autopilot Lambda receives a JSON payload with these fields:

- `pipeline` - the resolved pipeline definition (stages, steps, sleep_presets)
- `bundle_s3_uri` - S3 URI to the bundle zip
- `deploy_action` - one of: `apply`, `plan`, `destroy`, `sleep`, `wake`
- `git_sha` - commit SHA that triggered the build
- `only` - (optional) array of project names to target (others skipped)
- `deploy_mode` - (optional) `"autopilot"` (default) or `"supervised"`
- `sleep_preset` - (optional) preset name for sleep/wake actions
- `force` - (optional) boolean, bypasses sleeping pipeline guard on apply
- `destroy_all` - (optional) boolean, required safety flag for full destroy
