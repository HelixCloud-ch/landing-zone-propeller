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
import { checkConcurrentExecution } from "./services/lambda.js";
import { promoteActiveBundle } from "./services/s3.js";
import { writePipelineState } from "./services/ssm.js";
import type {
  PipelineContext,
  PipelineErrorCode,
  PipelineEvent,
  PipelineResult,
  StepResult,
} from "./types.js";

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
  const validationError = validateEvent(event);
  if (validationError) return validationError;

  const pipeline = event.pipeline;
  const only = new Set(event.only ?? []);

  const pctx: PipelineContext = {
    bundleS3Uri: event.bundle_s3_uri,
    deployAction: event.deploy_action ?? "apply",
    namespace: pipeline.namespace ?? "",
    propellerVersion: pipeline.propeller_version ?? "unknown",
    gitSha: event.git_sha ?? "",
    consumerTags: pipeline.consumer_tags ?? {},
    executionId: extractExecutionId(context),
    supervised: event.deploy_mode === "supervised",
  };

  // Prevent concurrent full-pipeline executions of the same namespace
  if (pctx.namespace && only.size === 0) {
    const currentArn = extractExecutionArn(context);
    const conflict = await checkConcurrentExecution(pctx.namespace, currentArn);
    if (conflict) {
      return fail(
        `Namespace '${pctx.namespace}' already has a running execution: ${conflict}`,
        "CONCURRENT_EXECUTION",
      );
    }
  }

  // Filter pipeline to only the specified projects (if set)
  if (only.size > 0) {
    for (const stage of pipeline.stages) {
      stage.steps = stage.steps.filter((s) => only.has(s.project));
    }
    pipeline.stages = pipeline.stages.filter((s) => s.steps.length > 0);
  }

  // Reverse stage order for sleep (tear down in reverse dependency order)
  const stages = pctx.deployAction === "sleep" ? [...pipeline.stages].reverse() : pipeline.stages;

  const clients = createClients(clientOverrides);
  const allResults = await runAllStages(stages, pctx, clients, context);

  return buildResult(allResults, pctx, clients);
}

export type { PipelineEvent, PipelineResult };

// ── Internals ──

function validateEvent(event: PipelineEvent): PipelineResult | null {
  if (!event.pipeline?.stages?.length)
    return fail("pipeline.stages is empty or missing", "VALIDATION_ERROR");
  if (!event.bundle_s3_uri) return fail("bundle_s3_uri is required", "VALIDATION_ERROR");
  if (!event.deploy_action) return fail("deploy_action is required", "VALIDATION_ERROR");
  return null;
}

function fail(error: string, errorCode?: PipelineErrorCode): PipelineResult {
  return {
    status: "failed",
    summary: { succeeded: 0, failed: 0, skipped: 0 },
    results: [],
    error,
    errorCode,
  };
}

async function runAllStages(
  stages: import("./types.js").Stage[],
  pctx: PipelineContext,
  clients: AWSClients,
  context: DurableContext,
): Promise<StepResult[]> {
  const allResults: StepResult[] = [];
  let stageFailed = false;

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

    const stageResults =
      pctx.deployAction === "sleep" || pctx.deployAction === "wake"
        ? await runStageSleepWake(stage, pctx, clients, context)
        : await runStage(stage, pctx, clients, context);

    allResults.push(...stageResults);

    if (stageResults.some((r) => r.status === "failed")) {
      stageFailed = true;
    }
  }

  return allResults;
}

async function buildResult(
  allResults: StepResult[],
  pctx: PipelineContext,
  clients: AWSClients,
): Promise<PipelineResult> {
  const totalFailed = allResults.filter((r) => r.status === "failed").length;
  const warnings: string[] = [];

  if (pctx.namespace && totalFailed === 0) {
    if (
      pctx.deployAction === "sleep" ||
      pctx.deployAction === "wake" ||
      pctx.deployAction === "apply"
    ) {
      const finalState = pctx.deployAction === "sleep" ? "sleeping" : "running";
      await writePipelineState(clients.ssm, pctx.namespace, finalState);
    }

    if (pctx.deployAction === "apply") {
      try {
        await promoteActiveBundle(pctx);
      } catch (err: unknown) {
        warnings.push(
          `Bundle promotion failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
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
    ...(warnings.length > 0 && { warnings }),
  };
}

function extractExecutionId(context: DurableContext): string {
  try {
    const arn = context.executionContext.durableExecutionArn;
    const parts = arn.split("/");
    return parts.length >= 3 ? parts[2]! : "";
  } catch {
    return "";
  }
}

function extractExecutionArn(context: DurableContext): string {
  try {
    return context.executionContext.durableExecutionArn;
  } catch {
    return "";
  }
}
