# Consumer Guide

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/HelixCloud-ch/landing-zone-propeller/main/consumer/init.sh | bash
```

Or pin a specific version:

```bash
curl -fsSL ... | bash -s -- --version v1.0.0
```

This creates the base structure: `justfile`, `propeller.overrides.yaml`,
`.gitignore`, `config/`, and `projects/`.

## Workflow

```bash
just pull       # Download framework at pinned version
just resolve    # Merge base pipeline + your overrides
just validate   # Check the resolved pipeline for errors
just bundle     # Create dist/bundle.zip
just upload     # Upload bundle to S3
just trigger    # Invoke the autopilot Durable Lambda
```

Shortcuts:

```bash
just build      # resolve + validate + bundle
just deploy     # build + upload + trigger
```

## Configuration

### `propeller.overrides.yaml`

Pins the framework version and defines pipeline customizations: target
remapping, project overrides/additions/removals, and stage reordering.
See the generated file for commented examples.

### `config/`

Per-project configuration files (e.g. `<project-name>.tfvars` for
Terraform projects).

### `projects/`

Custom projects not in the framework. Each needs a `project.yaml`
following the project contract.

## Environment Variables

- `PROPELLER_BUNDLE_BUCKET` - S3 bucket for bundles (required for upload/trigger)
- `PROPELLER_LAMBDA_ARN` - Autopilot Lambda ARN (`:$LATEST` is appended automatically if unqualified)
- `DEPLOY_ACTION` - `plan` or `apply` (default: `apply`)

## CI

See [consumer-ci.md](consumer-ci.md) for full setup. In short:

```yaml
- run: just pull
- run: just deploy
```

## How auto-update works

The `pull` recipe downloads the framework into `.propeller/` (gitignored).
Your root justfile imports recipes from `.propeller/consumer/justfile` via
`import?`. Since `.propeller/` is overwritten on every pull, recipes stay
in sync with the pinned version automatically.

The `pull` recipe itself lives in your root justfile so it works even
before `.propeller/` exists.

## Requirements

- [just](https://just.systems/)
- [uv](https://docs.astral.sh/uv/)
- [yq](https://github.com/mikefarah/yq)
- [jq](https://jqlang.github.io/jq/)
- curl, unzip
- AWS CLI (for upload/trigger)
