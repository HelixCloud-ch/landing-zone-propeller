# Propeller Documentation

Propeller is a pipeline framework for AWS multi-account landing zones. It
deploys and manages infrastructure with reproducible pipelines, cross-project
dependencies, and customization without forking the framework itself.

## Start here

For first-time readers, read in order. Each step builds on the previous one.

1. [Concepts](concepts.md) - what Propeller is and how the pieces fit together.
2. [Bootstrap](../bootstrap/README.md) - one-time setup of framework
   prerequisites.
3. [Consumer setup](consumer-setup.md) - create a consumer repo and configure
   the pipeline.
4. [CI setup](ci-setup.md) - configure GitHub Actions for ongoing deploys.

## Customize and operate

Once a pipeline is in place, these cover day-to-day tasks.

- [Customization](customization.md) - add, remove, override projects; insert new
  stages.

## Reference

Schemas, conventions, and lookups.

- [Pipeline schema](pipeline-schema.md) - `propeller.yaml` and
  `propeller.overrides.yaml` field reference.
- [Project structure](project-structure.md) - `project.yaml`, consumer overlays,
  project layout.
- [Glossary](glossary.md) - terminology used throughout.

## Internals

For framework contributors and the curious.

- [Architecture](architecture.md) - how the engine, Lambda, CodeBuild, and SSM
  fit together.
