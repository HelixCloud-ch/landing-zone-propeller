# Project structure

How a project lives on disk, what `project.yaml` declares, and how consumer
overlays merge with framework projects at bundle time.

A project is the on-disk source for one deployable unit. It's referenced by name
from a pipeline step, deployed into the step's `target` account, and
reads/writes data through the inputs and outputs declared in the pipeline. See
[pipeline-schema.md](pipeline-schema.md) for the wiring side.

## Layout by deploy type

Each project lives at `<pipeline>/projects/<project-name>/` and always contains
a `project.yaml`. The rest of the layout depends on the deploy type.

### Terraform

```
landing-zone/projects/control-tower-prerequisites/
├── project.yaml
├── README.md
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── providers.tf
    └── versions.tf
```

The engine runs Terraform from the `terraform/` directory. The backend is
configured by the engine from `project.yaml`; the project itself only declares
`backend "s3" {}` in `versions.tf`.

### CloudFormation

```
landing-zone/projects/some-cfn-project/
├── project.yaml
├── README.md
└── cloudformation/
    └── template.yaml
```

The engine runs `aws cloudformation deploy` against the template. Inputs
declared in the pipeline step are passed as `--parameter-overrides`. After a
successful apply, outputs are extracted from the deployed stack via
`describe-stacks`, written to `.propeller-outputs.json`, and promoted to SSM by
the Lambda according to the pipeline step's `outputs:` declaration.

Note: the CloudFormation runner is currently not aligned with the v2 project
contract (which moved `outputs:` from `project.yaml` to the pipeline step).

### Script

```
landing-zone/projects/example-script/
├── project.yaml
├── README.md
└── justfile
```

The engine delegates everything to `just` recipes. The justfile must implement:
`init`, `plan`, `apply`, `destroy`, `outputs`. Inputs are available as
`PROPELLER_INPUT_<var_name>` environment variables. The `apply` recipe is
responsible for writing outputs to `.propeller-outputs.json` in the project
directory.

## `project.yaml`

The project's self-description. Keep this minimal - all wiring (target, inputs,
outputs, dependencies) lives in the pipeline step, not here.

### Terraform

```yaml
name: control-tower-prerequisites
description: Control Tower prerequisites

deploy:
  type: terraform
  terraform:
    backend:
      bucket: "state-iac-${AWS_ACCOUNT_ID}-${AWS_REGION}-an"
      key: "propeller/${PROPELLER_NAMESPACE}/${PROJECT_NAME}/terraform.tfstate"
      region: "${AWS_REGION}"
```

### CloudFormation

```yaml
name: some-cfn-project
description: Example CloudFormation project

deploy:
  type: cloudformation
  cloudformation:
    stack_name: "${PROJECT_NAME}-${AWS_REGION}" # optional, defaults to project name
    region: "${AWS_REGION}" # optional, defaults to AWS_REGION env
    template: cloudformation/template.yaml # optional, this is the default
```

### Script

```yaml
name: example-script
description: Example script-based project

deploy:
  type: script
```

## Fields

- `name` - unique identifier within the pipeline. Must match the folder name.
- `description` - human-readable summary. Surfaces in tooling.
- `deploy.type` - `terraform`, `cloudformation`, or `script`.
- `deploy.terraform.backend` - S3 backend config, env-var substituted at deploy
  time.
- `deploy.cloudformation.{stack_name,region,template}` - all optional; sensible
  defaults apply.

## Environment-variable substitution

Strings inside `project.yaml` support `${VAR}` substitution at deploy time. The
following variables are populated automatically:

- `${AWS_ACCOUNT_ID}` - the target account ID for this step
- `${AWS_REGION}` - the deploy region
- `${PROPELLER_NAMESPACE}` - the pipeline's `namespace`
- `${PROJECT_NAME}` - the project's `name`

Substitution applies to any string field in `project.yaml`. The most common use
is templating the Terraform backend (bucket name, state key) so a single project
source can deploy into different accounts and namespaces without edits.

A missing variable causes the deploy to fail with an explicit error rather than
silently expanding to an empty string.

## Consumer overlays

Consumers customize framework projects by mirroring the project structure under
their own `<pipeline>/projects/<project-name>/` directory and dropping in
overlay files:

```
landing-zone/projects/control-tower-prerequisites/
└── terraform/
    └── config.auto.tfvars
```

Recognized overlay files:

- `config.auto.tfvars` (or any `*.auto.tfvars`) - Terraform variable values.
  Auto-loaded by Terraform at apply time.
- Terraform
  [override files](https://developer.hashicorp.com/terraform/language/files/override) -
  merged on top of same-named blocks in the rest of the configuration.

The bundle assembler copies the framework project first, then overlays consumer
files on top. Consumer files win on conflict.

### Custom (consumer-only) projects

Consumers can also add **brand-new projects** that don't exist in the framework.
The structure is the same; the consumer just provides the full project source
(not just an overlay):

```
landing-zone/projects/my-custom-project/
├── project.yaml
├── README.md
└── terraform/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

The pipeline-level addition (in `propeller.overrides.yaml`) points the step's
`source:` at the consumer-side path:

```yaml
pipeline:
  additions:
    - stage: foundation
      step:
        project: my-custom-project
        source: "./landing-zone/projects/my-custom-project"
        target: management
```

Custom projects are copied as-is into the bundle - no merge needed, nothing to
overlay against.

## See also

- [Pipeline schema](pipeline-schema.md) - the pipeline-side wiring (target,
  inputs, outputs, dependencies).
- [Customization](customization.md) - common patterns for adding, removing, and
  overriding projects.
- [Examples](examples/) - working reference projects to copy as starting
  points.
- [Glossary](glossary.md) - canonical terminology.
