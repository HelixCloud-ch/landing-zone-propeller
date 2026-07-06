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

metadata:
  cost-center: landing-zone

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

metadata:
  cost-center: landing-zone

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

metadata:
  cost-center: landing-zone

deploy:
  type: script
```

## Fields

- `name` - unique identifier within the pipeline. Must match the folder name.
- `description` - human-readable summary. Surfaces in tooling.
- `metadata.cost-center` - optional, becomes the `propeller:cost-center` tag on
  resources created by this project. Omit to skip the tag.
- `metadata.framework-required` - optional, set to `true` to emit
  `propeller:framework-required = true` on every resource (use only for
  resources that exist solely to run the framework, like CodeBuild projects and
  Lambda runners).
- `deploy.type` - `terraform`, `cloudformation`, or `script`.
- `deploy.terraform.backend` - S3 backend config, env-var substituted at deploy
  time.
- `deploy.cloudformation.{stack_name,region,template}` - all optional; sensible
  defaults apply.
- `sleep` - optional block declaring the project's sleep/wake capability. See
  [Sleep / Wake](#sleep--wake) below.

## Sleep / Wake

The `sleep:` block in `project.yaml` declares what should happen when the
platform enters sleep mode (cost optimization) and what happens on wake.

### Schema

```yaml
sleep:
  action: destroy | command | skip
  timeout: 120                       # optional, seconds (default: 60)
  command: |                         # required if action: command
    aws rds stop-db-instance ...
  wake_command: |                    # required if action: command
    aws rds start-db-instance ...
```

### Actions

| Action | On sleep | On wake | Use case |
|--------|----------|---------|----------|
| `destroy` | `terraform destroy` | `terraform apply` (recreate) | Clusters, caches, NAT gateways |
| `command` | Runs `sleep.command` | Runs `sleep.wake_command` | RDS stop/start, Oracle, Aurora |
| `skip` | No-op | No-op | VPCs, security groups, DNS |

If a project has no `sleep:` block, it has no sleep capability and cannot be
opted into sleep from the pipeline.

### How it works

1. The framework project declares the **capability** (how to sleep).
2. The consumer's pipeline step opts in with `sleep: true`.
3. On `DEPLOY_ACTION=sleep`, the engine reverses stage order and executes each
   project's declared sleep action.
4. On `DEPLOY_ACTION=wake`, the engine runs stages forward and recreates or
   restarts each project.

### Command variable resolution

Commands support `${VAR}` substitution. Available variables:

| Variable | Source |
|----------|--------|
| `${AWS_REGION}` | Target account region |
| `${AWS_ACCOUNT_ID}` | Target account ID |
| `${TF_OUTPUT_<name>}` | Terraform output from the project's own state |
| `${PROPELLER_NAMESPACE}` | Pipeline namespace |
| `${PROJECT_NAME}` | Project name |

### Examples

**Destroy/recreate** (EKS cluster, ElastiCache):

```yaml
name: eks-cluster
deploy:
  type: terraform
sleep:
  action: destroy
  timeout: 120
```

**Command** (RDS Oracle — stop/start via API):

```yaml
name: rds-oracle
deploy:
  type: terraform
sleep:
  action: command
  command: |
    aws rds stop-db-instance \
      --db-instance-identifier ${TF_OUTPUT_db_instance_identifier} \
      --region ${AWS_REGION}
  wake_command: |
    aws rds start-db-instance \
      --db-instance-identifier ${TF_OUTPUT_db_instance_identifier} \
      --region ${AWS_REGION}
    aws rds wait db-instance-available \
      --db-instance-identifier ${TF_OUTPUT_db_instance_identifier} \
      --region ${AWS_REGION}
```

**Pipeline step opt-in:**

```yaml
stages:
  - name: cluster
    steps:
      - project: eks-cluster-1
        source: eks-cluster
        target: my-account
        sleep: true              # participates in sleep/wake
```

### Triggering sleep/wake

```bash
# Sleep the platform
DEPLOY_ACTION=sleep just platform-deploy my-platform

# Wake the platform
DEPLOY_ACTION=wake just platform-deploy my-platform

# Sleep a single project
DEPLOY_ACTION=sleep ONLY=eks-cluster-1 just platform-deploy my-platform
```

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

## Tags

The framework injects a small set of tags on every resource it deploys.
Terraform projects expose three variables that the engine wires automatically:

```hcl
variable "tags"           { type = map(string)  default = {} }   # per-project
variable "consumer_tags"  { type = map(string)  default = {} }   # pipeline-wide
variable "propeller_tags" { type = map(string)  default = {} }   # framework

# providers.tf
default_tags {
  tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
}
```

Precedence (lowest to highest): `consumer_tags` → `tags` → `propeller_tags`.
Framework tags always win on key collisions; consumer per-project tags override
pipeline-wide ones.

Framework tags emitted automatically per project:

- `propeller:pipeline` - the pipeline's `namespace`
- `propeller:project` - the project name
- `propeller:deploy-type` - `terraform`, `cloudformation`, or `script`
- `propeller:cost-center` - from `metadata.cost-center` (only when set)
- `propeller:framework-required` - from `metadata.framework-required: true`
  (only when set to true)

CloudFormation projects receive the same tags via
`aws cloudformation deploy --tags`. Script projects receive them as
`PROPELLER_FRAMEWORK_TAGS_JSON` and `PROPELLER_CONSUMER_TAGS_JSON` environment
variables.

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
- [Examples](examples/) - working reference projects to copy as starting points.
- [Glossary](glossary.md) - canonical terminology.
