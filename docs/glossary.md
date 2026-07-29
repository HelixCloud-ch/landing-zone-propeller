# Glossary

<!-- Keep entries in alphabetical order when adding or moving terms. -->

Terms used consistently across the framework.

**Account** - an AWS account. We provision accounts. Account creation is also
called _vending_ (matching AFT terminology).

**Autopilot** - the Lambda in the Operations account that orchestrates a
pipeline run. Receives a bundle reference, walks the resolved pipeline, and
triggers CodeBuild jobs that run the project deploys. Supports `plan`, `apply`,
`destroy`, `sleep`, and `wake` actions. Runs as a durable execution for
reliable resumption.

**Barrier** - a stage property (default: `true`). When true, all steps in that
stage must complete before any step in the next stage starts. When false,
consecutive non-barrier stages are merged into a single execution group and
the DAG handles ordering across them.

**Bundle** - the deployment artifact. A zip of resolved pipeline + project
sources + consumer overlays + shared recipes + engine, uploaded to S3
(`bundles/{namespace}/{sha}.zip`) and consumed by the Autopilot Lambda.

**Consumer** - the user-facing repository that customizes the framework via
`propeller.overrides.yaml` (or a direct `propeller.yaml`) and project overlays.
Pins one framework version in `.propeller-version`.

**Execution group** - one or more stages merged together for execution.
Barrier stages form their own group. Consecutive non-barrier stages merge into
one group where the DAG handles all ordering.

**Framework** - this repository. Ships the engine, the Autopilot Lambda, the
consumer tooling, shared recipes, and a default landing-zone pipeline with its
set of projects.

**Framework tags** - the `propeller:*` tags injected by the engine on every
resource.

**Landing zone** - the org-wide foundation: the AWS Organization, OU structure,
governance accounts (log archive, audit, etc.), Control Tower configuration,
identity, and shared baselines. Everything that needs to exist before workload
accounts can be provisioned safely. Propeller's default pipeline implements
this.

**Namespace** - a per-pipeline identifier (e.g. `landing-zone`) used as the
prefix for SSM keys and Terraform state keys. Isolates pipelines so two
pipelines in the same consumer can have a project with the same name without
colliding.

**Operations account** - the AWS account that hosts the Autopilot Lambda and the
source bundle bucket. Propeller deployments are orchestrated from here.
Typically also the home for other shared operations tooling.

**Overlay** - consumer-side files that mirror a framework project's structure to
inject `config.auto.tfvars` and optional `overrides.tf`. Merged with the
framework's project source at bundle time.

**Pipeline** - one YAML document describing stages and steps. Maps to one
Durable Lambda invocation. Examples: the landing-zone pipeline, or a per-account
platform pipeline.

**Platform** - the infrastructure (e.g. EKS, RDS, networking) deployed into one
or more workload accounts to support a workload. A platform is composed by one
pipeline; that pipeline can target a single account or span several related
accounts (e.g. prod plus a dedicated DR account). A single building block (an
EKS project, an RDS project) is a _platform project_.

**Project** - a deployable unit on disk: a Terraform module, CloudFormation
template, or script. Lives at `<pipeline>/projects/<name>/`. Described by
`project.yaml`.

**Stage** - an ordered group of steps within a pipeline. By default stages act
as barriers (sequential). Set `barrier: false` to allow parallel execution with
adjacent non-barrier stages via the DAG.

**Step** - one project deployment within a stage. Steps within a stage (or
execution group) run in parallel unless data dependencies serialize them.

**Supervised mode** - a deploy mode (`deploy_mode: "supervised"`) where every
project pauses after plan for approval before proceeding to apply. Can also be
enabled per-project with `approval: "required"`.

**Sleep preset** - a named mapping of project names to sleep modes, declared in
the pipeline YAML under `sleep_presets`. Determines which projects participate
in a sleep/wake cycle and how each one sleeps.

**Sleep mode** - the strategy a project uses to sleep. Common modes: `destroy`
(tf-destroy/apply), `stop` (API stop/start), `snapshot` (targeted destroy with
final snapshot). Projects implement modes as `sleep-{mode}` and `wake-{mode}`
recipes in their justfile.

**Target** - the AWS account a step runs against.

**Workload** - a set of applications and the resources they need, treated as a
unit. Runs on top of a platform. Matches AWS's use of the term.

**Workload account** - an AWS account that hosts a workload. Platforms are
deployed into workload accounts. A workload may span more than one account.

**Workloads OU** - the organizational unit (and any nested OUs beneath it) that
contains workload accounts.
