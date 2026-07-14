/**
 * Propeller Autopilot — Lambda handler entry point.
 *
 * Wraps the pipeline execution in a durable execution context for
 * reliable, resumable processing of multi-stage deployments.
 */

import type { DurableContext } from "@aws/durable-execution-sdk-js";
import { withDurableExecution } from "@aws/durable-execution-sdk-js";
import { runStageSleepWake } from "./pipeline/sleep.js";
import { runStage } from "./pipeline/stage.js";
import type { AWSClients } from "./services/aws.js";
import { createClients } from "./services/aws.js";
import { writePipelineState } from "./services/ssm.js";
import type { PipelineContext, PipelineEvent, PipelineResult, StepResult } from "./types.js";

export const handler = withDurableExecution(
  async (event: PipelineEvent, context: DurableContext): Promise<PipelineResult> => {
    return execute(event, context);
  },
);

export async function execute(
  event: PipelineEvent,
  context: DurableContext,
  clientOverrides?: Partial<AWSClients>,
): Promise<PipelineResult> {
  const fail = (error: string): PipelineResult => ({
    status: "failed",
    summary: { succeeded: 0, failed: 0, skipped: 0 },
    results: [],
    error,
  });

  if (!event.pipeline?.stages?.length) return fail("pipeline.stages is empty or missing");
  if (!event.bundle_s3_uri) return fail("bundle_s3_uri is required");
  if (!event.deploy_action) return fail("deploy_action is required");

  const pipeline = event.pipeline;
  const only = new Set(event.only ?? []);

  const pctx: PipelineContext = {
    bundleS3Uri: event.bundle_s3_uri,
    deployAction: event.deploy_action ?? "apply",
    namespace: pipeline.namespace ?? "",
    propellerVersion: pipeline.propeller_version ?? "unknown",
    gitSha: event.git_sha ?? "",
    consumerTags: pipeline.consumer_tags ?? {},
    executionId: (context as any).executionId ?? "",
    supervised: event.deploy_mode === "supervised",
  };

  // Filter pipeline to only the specified projects (if set)
  if (only.size > 0) {
    for (const stage of pipeline.stages) {
      stage.steps = stage.steps.filter((s) => only.has(s.project));
    }
    pipeline.stages = pipeline.stages.filter((s) => s.steps.length > 0);
  }

  // Reverse stage order for sleep (tear down in reverse dependency order)
  let stages = pipeline.stages;
  if (pctx.deployAction === "sleep") {
    stages = [...stages].reverse();
  }

  const allResults: StepResult[] = [];
  let stageFailed = false;
  const clients = createClients(clientOverrides);

  for (const stage of stages) {
    if (stageFailed) {
      for (const step of stage.steps) {
        allResults.push({
          status: "skipped",
          project: step.project,
          error: "previous stage failed",
        });
      }
      continue;
    }

    let stageResults: StepResult[];

    if (pctx.deployAction === "sleep" || pctx.deployAction === "wake") {
      stageResults = await runStageSleepWake(stage, pctx, clients, context);
    } else {
      stageResults = await runStage(stage, pctx, clients, context);
    }

    allResults.push(...stageResults);

    const failedCount = stageResults.filter((r) => r.status === "failed").length;
    if (failedCount > 0) {
      stageFailed = true;
    }
  }

  // Write pipeline state and promote active bundle on success
  const totalFailed = allResults.filter((r) => r.status === "failed").length;
  if (pctx.namespace && totalFailed === 0) {
    if (
      pctx.deployAction === "sleep" ||
      pctx.deployAction === "wake" ||
      pctx.deployAction === "apply"
    ) {
      const finalState = pctx.deployAction === "sleep" ? "sleeping" : "running";
      await writePipelineState(clients.ssm, pctx.namespace, finalState);
    }

    // Promote bundle to active (only on successful apply)
    if (pctx.deployAction === "apply") {
      await promoteActiveBundle(pctx);
    }
  }

  return {
    status: totalFailed > 0 ? "failed" : "succeeded",
    summary: {
      succeeded: allResults.filter((r) => r.status === "succeeded").length,
      failed: totalFailed,
      skipped: allResults.filter((r) => r.status === "skipped").length,
    },
    results: allResults,
  };
}

export type { PipelineEvent, PipelineResult };

async function promoteActiveBundle(pctx: PipelineContext): Promise<void> {
  const { S3Client, CopyObjectCommand } = await import("@aws-sdk/client-s3");

  const sourceUri = pctx.bundleS3Uri.replace("s3://", "");
  const bucket = sourceUri.split("/")[0]!;
  const activeKey = `active/${pctx.namespace}/bundle.zip`;

  const s3 = new S3Client({});

  await s3.send(
    new CopyObjectCommand({
      Bucket: bucket,
      CopySource: sourceUri,
      Key: activeKey,
      MetadataDirective: "REPLACE",
      Metadata: {
        "bundle-s3-uri": pctx.bundleS3Uri,
        "git-sha": pctx.gitSha,
        "propeller-version": pctx.propellerVersion,
        "execution-id": pctx.executionId,
        "deploy-action": pctx.deployAction,
        "promoted-at": new Date().toISOString(),
      },
    }),
  );
}
