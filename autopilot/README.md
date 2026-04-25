# Autopilot

Durable Lambda that orchestrates pipeline execution across accounts. Stages run
sequentially; steps within a stage run in parallel waves based on their
`depends_on` graph.

## How it works

1. Receives a resolved pipeline + bundle S3 URI as input
2. For each stage, builds a DAG of steps and runs them in parallel waves
3. Each step assumes a cross-account role, starts a CodeBuild build, and polls
   until completion
4. Outputs are written to SSM for downstream steps to consume
5. If a step fails, its transitive dependents are skipped

## Deployment

Deployed during the bootstrap phase.

```bash
$RUN deploy-autopilot.sh
```
