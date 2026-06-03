# Customization

Common patterns for adapting the framework's default pipeline to a specific
environment, without forking. Pair with the schema reference in
[pipeline-schema.md](pipeline-schema.md).

All customization happens in two places:

- `landing-zone/propeller.overrides.yaml` - pipeline-level changes (target
  remapping, additions, removals, stage reordering, pipeline-wide tags).
- `landing-zone/projects/<name>/terraform/config.auto.tfvars` - per-project
  Terraform variable values. Mirrors the framework project structure;
  auto-loaded by Terraform at apply time.

Run `just resolve` after any change to see the resolved pipeline at
`dist/pipeline.lock.yaml` and the Mermaid graph at `dist/pipeline.lock.md`. Use
this to verify the result before committing.

## Set tags pipeline-wide

Common tags applied to every project's resources go in
`propeller.overrides.yaml`:

```yaml
tags:
  "acme:cost-center": "platform"
  "acme:environment": "dev"
```

These are merged into provider `default_tags` for all framework projects.
Per-project tag overrides go in that project's `config.auto.tfvars`:

```hcl
tags = { "acme:project" = "eks" }
```

Per-project values take precedence over pipeline-wide ones. Framework tags
(`propeller:*`) always win over both.

## Set Terraform variables for a framework project

Most customization is just setting the right tfvars on framework projects.
Mirror the project structure under `landing-zone/projects/`, drop in
`config.auto.tfvars`:

```
landing-zone/
└── projects/
    └── control-tower-prerequisites/
        └── terraform/
            └── config.auto.tfvars
```

```hcl
region                       = "eu-central-2"
log_archive_account_email    = "aws+log-archive@example.com"
audit_account_email          = "aws+audit@example.com"
backup_admin_account_email   = "aws+backup-admin@example.com"
backup_central_account_email = "aws+backup-central@example.com"
```

The assembler merges this overlay onto the framework's project at bundle time.
Consumer values win on conflict.

For the full list of variables a project accepts, read its `variables.tf` and
`README.md` under `.propeller/landing-zone/projects/<name>/`.

## Remap a project to a different target account

The framework defaults all foundation projects to the `management` account. To
deploy a project into a different account instead:

```yaml
pipeline:
  targets:
    base-sso: sandbox
```

The named account must be resolvable to an account ID by the engine (via the SSM
account registry under `/propeller/accounts/`). You can also use this for
testing something in a sandbox if you have a such environment.

## Add a custom project to an existing stage

Place the project under `landing-zone/projects/<name>/` with the full source
(`project.yaml`, `terraform/`, etc.), then add a step to the relevant stage:

```yaml
pipeline:
  additions:
    - stage: foundation
      step:
        project: scp-baseline
        source: "./landing-zone/projects/scp-baseline"
        target: management
        depends_on: [control-tower]
        outputs:
          - name: scp_attached
```

`source:` points at the consumer-side project directory. The custom project is
bundled as-is alongside framework projects.

## Insert a new stage between existing ones

For changes that need their own phase boundary (run after one existing stage but
before the next), use `after:` and the plural `steps:` form:

```yaml
pipeline:
  additions:
    - stage: governance
      after: foundation
      steps:
        - project: scp-baseline
          source: "./landing-zone/projects/scp-baseline"
          target: management
        - project: tag-policies
          source: "./landing-zone/projects/tag-policies"
          target: management
```

Stages run sequentially, so anything in `governance` finishes before the next
stage starts.

## Remove a framework project

To exclude a project entirely:

```yaml
pipeline:
  removals:
    - project: base-sso
```

The resolver also strips `base-sso` from any `depends_on` lists in remaining
projects. If a downstream project reads outputs from the removed project, the
resolver fails fast at resolve time pointing at the broken wiring.

## Replace a framework project with a local fork

When a framework project is mostly right but needs deeper changes than overlay
files (`config.auto.tfvars`, `overrides.tf`) allow, point the existing step at a
consumer-side source:

```yaml
pipeline:
  overrides:
    - project: base-sso
      source: "./landing-zone/projects/custom-base-sso"
```

The step keeps its position, target, and wiring; only the source changes. Use
this for rare cases where overlay files (`overrides.tf`, `config.auto.tfvars`)
aren't enough. Forking pulls the project out of the framework's upgrade path -
you'll need to manually keep it current with framework changes.

## Verify customizations

After any override edit, the typical loop:

```bash
just resolve     # produces dist/pipeline.lock.yaml + .md
```

Then open `dist/pipeline.lock.md` for the Mermaid graph view, or inspect
`dist/pipeline.lock.yaml` for the full resolved pipeline.

A plan from CI (or `DEPLOY_ACTION=plan` from a maintainer's machine) is the
final check before applying.

## See also

- [Pipeline schema](pipeline-schema.md) - field-by-field reference for
  `propeller.yaml` and `propeller.overrides.yaml`.
- [Project structure](project-structure.md) - how a project is laid out on disk
  and how overlays merge.
- [Glossary](glossary.md) - terminology used throughout.
