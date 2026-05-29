# Concepts

A short mental model of how Propeller works. Read this first.

## What it is

Propeller deploys AWS landing zones across many accounts. A landing zone has a
lot of moving parts (organization, accounts, OUs, Control Tower, identity) that
need to land in the right order and exchange information as they go (account
IDs, role ARNs, OU IDs). Propeller coordinates all of that.

The framework ships an opinionated default landing zone. Adopters take the
default, customize what they need, and deploy. There is no forking, so adopting
framework improvements (new features, fixes, better defaults) is a version bump,
not a merge conflict.

## How it's organized

The starting point is a **pipeline** described by one YAML file. A pipeline is a
sequence of **stages**; each stage is a group of **steps**; each step deploys a
**project**.

```
pipeline (propeller.yaml)
└── stage: foundation
    ├── step: control-tower-prerequisites
    ├── step: control-tower
    └── step: ou-infrastructure
└── stage: identity
    └── step: base-sso
```

Stages run in order. Steps inside a stage run in parallel when they can, in
sequence when one needs another's output. A project is the actual code that gets
deployed (Terraform, CloudFormation, or a script).

## Framework and consumer

Propeller has two halves.

The **framework** is this repository. It ships the engine, the default landing
zone pipeline, all its projects, and the infrastructure that runs deployments.

The **consumer** is the user-facing repository. It pins a framework version and
holds the customizations: which framework projects to configure, which to add,
which to remove. The consumer never edits or forks the framework; it overlays on
top.

A deploy combines both halves and runs them through the framework's
infrastructure.

## What a deploy does

The consumer's CI builds a deployment artifact, uploads it to AWS, and asks
Propeller to apply it. Propeller walks the pipeline, deploys each step into its
target account, and captures outputs so later steps can use them.

That's the loop.

## What's next

- Setting up a fresh AWS org: [bootstrap](../bootstrap/README.md).
- Org already bootstrapped: [consumer setup](consumer-setup.md).
- Reference for the schemas: [pipeline-schema](pipeline-schema.md) and
  [project-structure](project-structure.md).
- Terminology: [glossary](glossary.md).
