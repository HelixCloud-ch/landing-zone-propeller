# Triggering deploys from an external CI as a Proxy

This is one option, not the default. The usual path is GitHub Actions running
the consumer justfile directly and invoking the Autopilot ([ci-setup](ci-setup.md)).

Use this pattern when the CI can't run the framework toolchain itself (Jenkins,
GitLab, a locked-down runner): the CI only uploads the repo and starts a build;
the bundling and Autopilot invocation happen inside the deploy-runner CodeBuild.

## Flow

1. Zip the repo at a git sha and upload it to `sources/<sha>.zip` in the source
   bucket (`source-<account>-<region>-an`).
2. Start the deploy-runner CodeBuild with `--source-type-override S3`,
   `--source-location-override <bucket>/sources/<sha>.zip`, a
   `--buildspec-override`, and the deploy parameters as env vars.
3. The build runs `just pull` then `just deploy` / `just platform-deploy`, which
   bundle the pipeline and invoke the Autopilot. It exports
   `PROPELLER_EXECUTION_ID`.
4. Poll `executions/<PROPELLER_EXECUTION_ID>/status.json` in the same bucket
   until the execution finishes.

Deploy parameters (`PLATFORM`, `GIT_SHA`, `DEPLOY_ACTION`, `ONLY`, `DEPLOY_MODE`,
`SLEEP_PRESET`, `DESTROY_ALL`) match the [ci-setup](ci-setup.md) env vars.

## Monitoring

The Autopilot writes to the source bucket:

- `executions/<id>/status.json` — live execution state
- `logs/<id>/<project>.<action>.log` — per-step logs

`<id>` is the durable execution name, `namespace__action__sha__timestamp`. The
consumer justfile mints it and the buildspec exports it as
`PROPELLER_EXECUTION_ID`.

`status.json`:

```json
{
  "status": "running", // running | succeeded | failed
  "summary": { "succeeded": 1, "failed": 0, "skipped": 0 },
  "steps": [
    { "project": "network-vpc", "status": "succeeded" },
    { "project": "eks-cluster", "status": "running" }
  ],
  "events": [
    {
      "type": "step_succeeded",
      "project": "network-vpc",
      "log": "logs/<id>/network-vpc.apply.log"
    }
  ]
}
```

Poll until `status` is no longer `running`. `step_succeeded` / `step_failed`
events carry the log path for that step.

## IAM

The CI principal needs: `s3:PutObject` on `sources/*`, `s3:GetObject` on
`executions/*` and `logs/*`, and `codebuild:StartBuild` +
`codebuild:BatchGetBuilds` on the deploy-runner project. Deploy
[deploy-trigger-policy.yaml](examples/ci/deploy-trigger-policy.yaml) in the
Operations account and attach the output policy to your CI role or user.

## Examples

- [examples/ci/buildspec.yaml](examples/ci/buildspec.yaml) — reference buildspec
- [examples/ci/deploy-trigger-policy.yaml](examples/ci/deploy-trigger-policy.yaml) — IAM policy (CloudFormation)
