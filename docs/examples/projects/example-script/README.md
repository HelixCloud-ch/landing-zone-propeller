# example-script

Minimal script project. Demonstrates:

- The five required just recipes (`init`, `plan`, `apply`, `destroy`,
  `outputs`).
- Reading multiple inputs from `PROPELLER_INPUT_*` environment variables, with
  optional defaults via `env("VAR", "fallback")`.
- Reading framework and consumer tags from `PROPELLER_FRAMEWORK_TAGS_JSON` and
  `PROPELLER_CONSUMER_TAGS_JSON` (JSON maps), merging them with `jq`, and
  applying via `aws ... --tags`.
- Writing multiple outputs to `.propeller-outputs.json`. The pipeline step's
  `outputs:` declaration decides which of these keys get persisted to SSM; the
  project itself can write more than the pipeline consumes.

Use this as a starting point for projects that don't fit the Terraform or
CloudFormation runners (custom CLIs, external systems, shell-driven workflows).
