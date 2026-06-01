# example-script

Minimal script project. Demonstrates:

- The five required just recipes (`init`, `plan`, `apply`, `destroy`,
  `outputs`).
- Reading multiple inputs from `PROPELLER_INPUT_*` environment variables, with
  optional defaults via `env("VAR", "fallback")`.
- Writing multiple outputs to `.propeller-outputs.json`. The pipeline step's
  `outputs:` declaration decides which of these keys get persisted to SSM; the
  project itself can write more than the pipeline consumes.

Use this as a starting point for projects that don't fit the Terraform or
CloudFormation runners (custom CLIs, external systems, shell-driven workflows).
