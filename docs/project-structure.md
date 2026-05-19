# Project Structure

Each project lives under `<pipeline>/projects/<project-name>/`:

```
landing-zone/projects/hello-operations/
├── project.yaml
├── README.md
└── terraform/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

For script-based projects, replace `terraform/` with a `justfile`:

```
landing-zone/projects/hello-operations/
├── project.yaml
└── justfile
```

The justfile must provide recipes: `init`, `plan`, `apply`, `destroy`,
`outputs`. The `apply` recipe writes outputs to `.propeller-outputs.json`.
Inputs are available as `PROPELLER_INPUT_*` environment variables.

## `project.yaml`

Defines the project's name and deploy configuration.

```yaml
name: hello-operations
deploy:
  type: terraform
  terraform:
    backend:
      bucket: "state-iac-${AWS_ACCOUNT_ID}-${AWS_REGION}-an"
      key: "propeller/${PROPELLER_NAMESPACE}/${PROJECT_NAME}/terraform.tfstate"
      region: "${AWS_REGION}"
```

Fields:
- `name` - unique identifier (must match folder name)
- `deploy.type` - `terraform`, `cloudformation`, or `script`
- `deploy.terraform.backend` - S3 backend config with env var substitution

Target, inputs, outputs, and dependencies are defined in the pipeline
(see [pipeline-schema.md](pipeline-schema.md)).

## Consumer overlays

Consumers customize framework projects by mirroring the project structure:

```
landing-zone/projects/hello-operations/
└── terraform/
    └── config.auto.tfvars
```

Supported overlay files:
- `config.auto.tfvars` or `*.auto.tfvars`
- `overrides.tf`

These are merged on top of the framework project at bundle time.
