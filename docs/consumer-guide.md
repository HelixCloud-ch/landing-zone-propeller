# Consumer Guide

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/HelixCloud-ch/landing-zone-propeller/main/consumer/init.sh | bash
```

Or pin a specific version:

```bash
curl -fsSL ... | bash -s -- --version v1.0.0
```

This creates: `justfile`, `.gitignore`, and `landing-zone/` with
`propeller.overrides.yaml` and an empty `projects/` directory.

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

### `landing-zone/propeller.overrides.yaml`

Pins the framework version and defines pipeline customizations: target
remapping, project overrides/additions/removals, and stage reordering.
See the generated file for commented examples.

### `landing-zone/projects/`

Per-project customizations and custom projects. For framework projects,
provide `config.auto.tfvars` (and optional `overrides.tf`) mirroring the
project structure. Custom projects include the full source.

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
