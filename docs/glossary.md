# Glossary

<!-- Keep entries in alphabetical order when adding or moving terms. -->

Terms used consistently across the framework.

**Account** - an AWS account. We provision accounts. Account creation is also
called _vending_ (matching AFT terminology).

**Autopilot** - the Lambda in the Operations account that orchestrates a
pipeline run. Receives a bundle reference, walks the resolved pipeline, and
triggers CodeBuild jobs that run the project deploys. Supports both `plan` and
`apply` actions; manual approval gates between them are planned.

**Bundle** - the deployment artifact. Mainly a zip of resolved pipeline +
project sources + consumer overlays, uploaded to S3 and consumed by the
Autopilot Lambda.

**Consumer** - the user-facing repository that customizes the framework via
`propeller.overrides.yaml` and project overlays. Each pipeline can pin its own
framework version independently.

**Framework** - this repository. Ships the engine, the Autopilot Lambda, the
consumer tooling, and a default landing-zone pipeline with its set of projects.

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
or more accounts to support a workload. Each platform has its own pipeline; that
pipeline can target a single account or span several related accounts (e.g. prod
plus a dedicated DR account).

**Project** - a deployable unit on disk: a Terraform module, CloudFormation
template, or script. Lives at `<pipeline>/projects/<name>/`. Described by
`project.yaml`.

**Stage** - an ordered group of steps within a pipeline. Stages run
sequentially.

**Step** - one project deployment within a stage. Steps within a stage run in
parallel unless data dependencies serialize them.

**Target** - the AWS account a step runs against.
