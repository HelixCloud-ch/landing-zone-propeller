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
import { readPipelineState, writePipelineState } from "./services/ssm.js";
import type {
  PipelineContext,
  PipelineDefinition,
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
  const clients = createClients(clientOverrides);

  const pctx: PipelineContext = {
    bundleS3Uri: event.bundle_s3_uri,
    deployAction: event.deploy_action ?? "apply",
    namespace: pipeline.namespace ?? "",
    propellerVersion: pipeline.propeller_version ?? "unknown",
    gitSha: event.git_sha ?? "",
    consumerTags: pipeline.consumer_tags ?? {},
    executionId: extractExecutionId(context),
    supervised: event.deploy_mode === "supervised",
    sleepModes: {},
  };

  // Resolve sleep preset into per-project mode map
  if (
    (pctx.deployAction === "sleep" || pctx.deployAction === "wake") &&
    pipeline.sleep_presets
  ) {
    const presetName = event.sleep_preset ?? "";
    if (pctx.deployAction === "sleep" && !presetName) {
      return fail("sleep requires a sleep_preset name", "VALIDATION_ERROR");
    }
    // On wake, fall back to stored preset if none specified
    let resolvedPreset = presetName;
    if (pctx.deployAction === "wake" && !resolvedPreset) {
      const storedState = await readPipelineState(clients.ssm, pctx.namespace);
      resolvedPreset = storedState?.sleep_preset ?? "";
      // Use stored per-project modes if available (prevents drift if presets changed)
      if (storedState?.sleep_modes && Object.keys(storedState.sleep_modes).length > 0) {
        pctx.sleepModes = storedState.sleep_modes;
        resolvedPreset = "__stored__"; // skip preset lookup below
      }
      if (!resolvedPreset) {
        return fail(
          "wake requires a sleep_preset (none stored from previous sleep)",
          "VALIDATION_ERROR",
        );
      }
    }
    if (resolvedPreset !== "__stored__") {
      const modes = pipeline.sleep_presets[resolvedPreset];
      if (!modes) {
        return fail(
          `sleep_preset '${resolvedPreset}' not found in pipeline.sleep_presets`,
          "VALIDATION_ERROR",
        );
      }
      pctx.sleepModes = modes;
    }
  }

  // Block apply on sleeping pipelines unless force is set
  if (pctx.deployAction === "apply" && !event.force && pctx.namespace) {
    const state = await readPipelineState(clients.ssm, pctx.namespace);
    if (state?.state === "sleeping") {
      return fail(
        `Pipeline '${pctx.namespace}' is sleeping. Wake first or pass force: true.`,
        "SLEEPING_PIPELINE",
      );
    }
  }

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

  // Destroy safety: require explicit project list or destroy_all flag
  if (pctx.deployAction === "destroy" && only.size === 0 && !event.destroy_all) {
    return fail(
      "destroy requires 'only' (project list) or 'destroy_all: true' to destroy all projects",
      "VALIDATION_ERROR",
    );
  }

  // Reverse stage order for destructive actions (tear down in reverse dependency order)
  const stages =
    pctx.deployAction === "sleep" || pctx.deployAction === "destroy"
      ? [...pipeline.stages].reverse()
      : pipeline.stages;

  const allResults = await runAllStages(stages, pctx, clients, context);

  return buildResult(allResults, pctx, clients, pipeline, event.sleep_preset);
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
  let groupFailed = false;

  const groups = buildExecutionGroups(stages);

  for (const group of groups) {
    if (groupFailed) {
      for (const step of group.steps) {
        allResults.push({
          status: "skipped",
          project: step.project,
          error: "previous group failed",
        });
      }
      continue;
    }

    const mergedStage: import("./types.js").Stage = {
      name: group.name,
      steps: group.steps,
    };

    const groupResults =
      pctx.deployAction === "sleep" || pctx.deployAction === "wake"
        ? await runStageSleepWake(mergedStage, pctx, clients, context)
        : await runStage(mergedStage, pctx, clients, context);

    allResults.push(...groupResults);

    if (groupResults.some((r) => r.status === "failed")) {
      groupFailed = true;
    }
  }

  return allResults;
}

interface ExecutionGroup {
  name: string;
  steps: import("./types.js").StepConfig[];
}

/**
 * Build execution groups from stages.
 *
 * Consecutive stages with `barrier: false` are merged into a single group.
 * Stages with `barrier: true` (default) form their own group.
 * Within a merged group, the DAG handles all ordering.
 */
function buildExecutionGroups(stages: import("./types.js").Stage[]): ExecutionGroup[] {
  const groups: ExecutionGroup[] = [];
  let accumulator: { names: string[]; steps: import("./types.js").StepConfig[] } | null = null;

  for (const stage of stages) {
    const isBarrier = stage.barrier !== false; // default true

    if (isBarrier) {
      // Flush any accumulated non-barrier stages
      if (accumulator) {
        groups.push({
          name: accumulator.names.join("+"),
          steps: accumulator.steps,
        });
        accumulator = null;
      }
      // Barrier stage is its own group
      groups.push({ name: stage.name, steps: stage.steps });
    } else {
      // Non-barrier: accumulate
      if (!accumulator) {
        accumulator = { names: [], steps: [] };
      }
      accumulator.names.push(stage.name);
      accumulator.steps.push(...stage.steps);
    }
  }

  // Flush remaining
  if (accumulator) {
    groups.push({
      name: accumulator.names.join("+"),
      steps: accumulator.steps,
    });
  }

  return groups;
}

async function buildResult(
  allResults: StepResult[],
  pctx: PipelineContext,
  clients: AWSClients,
  pipeline: PipelineDefinition,
  sleepPreset?: string,
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
      await writePipelineState(
        clients.ssm,
        pctx.namespace,
        finalState,
        pctx.deployAction === "sleep" ? sleepPreset : undefined,
        pctx.deployAction === "sleep" ? pctx.sleepModes : undefined,
      );
    }

    if (pctx.deployAction === "apply") {
      try {
        await promoteActiveBundle(pctx, pipeline);
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
