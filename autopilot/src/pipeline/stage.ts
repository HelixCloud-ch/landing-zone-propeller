/**
 * Stage execution engine for the Propeller Autopilot.
 *
 * Handles wave-based parallel execution within stages, respecting
 * the DAG ordering and propagating failures to dependents.
 *
 * Execution timeline shape:
 *
 *   wave:<stage>:<n> (Parallel)
 *     <project> (NamedBranch)
 *       plan (RunInChildContext)
 *       approval (WaitForCallback)   ← only when approval required
 *       apply (RunInChildContext)
 */

import type { DurableContext } from "@aws/durable-execution-sdk-js";
import { POLL_INTERVAL_SECONDS, TERMINAL_BUILD_STATUSES } from "../constants.js";
import type { AWSClients } from "../services/aws.js";
import { createCloudWatchLogsClient, createCodeBuildClient } from "../services/aws.js";
import { fetchBuildLogs, pollBuild, startBuild } from "../services/codebuild.js";
import { writeLogs } from "../services/s3.js";
import { prepareBuildConfig, writeOutputs } from "../services/ssm.js";
import type { BuildConfig, PipelineContext, Stage, StepConfig, StepResult } from "../types.js";
import { buildDag, findDependents, findReady, reverseDag } from "./dag.js";

export async function runStage(
  stage: Stage,
  pctx: PipelineContext,
  clients: AWSClients,
  durableCtx: DurableContext,
): Promise<StepResult[]> {
  const steps = stage.steps;
  const stepMap = new Map(steps.map((s) => [s.project, s]));
  const rawDag = buildDag(steps);
  const dag =
    pctx.deployAction === "destroy" || pctx.deployAction === "sleep" ? reverseDag(rawDag) : rawDag;

  const completed = new Set<string>();
  const failed = new Set<string>();
  const skipped = new Set<string>();
  const results = new Map<string, StepResult>();
  let waveNum = 0;

  while (completed.size + failed.size + skipped.size < dag.size) {
    const ready = findReady(dag, completed, failed, skipped);
    if (ready.length === 0) break;

    const branches = ready.map((project) => ({
      name: project,
      func: async (branchCtx: DurableContext): Promise<StepResult> => {
        const step = stepMap.get(project);
        if (!step) return { status: "failed", project, error: "project not found in stage" };
        return executeStep(step, pctx, clients, branchCtx);
      },
    }));

    const batchResults = await durableCtx.parallel(`wave:${stage.name}:${waveNum}`, branches);
    const batchArray = batchResults.getResults() as StepResult[];

    for (const r of batchArray) {
      results.set(r.project, r);
      if (r.status === "succeeded") {
        completed.add(r.project);
      } else {
        failed.add(r.project);
        for (const dep of findDependents(dag, r.project)) {
          if (!completed.has(dep) && !failed.has(dep)) {
            skipped.add(dep);
            results.set(dep, {
              status: "skipped",
              project: dep,
              error: `dependency '${r.project}' failed`,
            });
          }
        }
      }
    }
    waveNum++;
  }

  return [...results.values()];
}

/**
 * Executes a single project step with plan/approval/apply as sibling contexts.
 *
 * When approval is required, the timeline shows:
 *   plan → approval (waitForCallback) → apply
 * as three distinct operations at the branch level.
 *
 * When no approval is needed, a single child context wraps the full action.
 */
export async function executeStep(
  step: StepConfig,
  pctx: PipelineContext,
  clients: AWSClients,
  branchCtx: DurableContext,
): Promise<StepResult> {
  const project = step.project;
  const log = branchCtx.logger;

  await pctx.statusTracker?.stepStarted(project);

  try {
    let result: StepResult;
    if (pctx.deployAction === "apply" && requiresApproval(step, pctx)) {
      result = await executeSupervisedStep(step, pctx, clients, branchCtx);
    } else {
      result = await executeDirectStep(step, pctx, clients, branchCtx);
    }

    if (result.status === "succeeded") {
      log.info(`✓ [${project}] succeeded`);
    } else {
      log.info(`✗ [${project}] failed: ${result.error}`);
    }

    await pctx.statusTracker?.stepCompleted(project, result.status as "succeeded" | "failed");
    return result;
  } catch (err: unknown) {
    const error = err instanceof Error ? err.message : String(err);
    log.error(`✗ [${project}] failed: ${error}`);
    await pctx.statusTracker?.stepCompleted(project, "failed");
    return {
      status: "failed",
      project,
      error,
    };
  }
}

/**
 * Direct execution: single child context for the full deploy action (plan, apply, destroy, etc).
 * Used when no approval gate is needed.
 */
async function executeDirectStep(
  step: StepConfig,
  pctx: PipelineContext,
  clients: AWSClients,
  branchCtx: DurableContext,
): Promise<StepResult> {
  const project = step.project;

  return branchCtx.runInChildContext(`${pctx.deployAction}`, async (ctx) => {
    const config: BuildConfig = await ctx.step(`prepare`, () =>
      prepareBuildConfig(clients.ssm, step, pctx.namespace),
    );

    const cbClient = await createCodeBuildClient(
      clients.sts,
      config.accountId,
      config.region,
      config.runner,
    );

    const buildId: string = await ctx.step(`build`, () => startBuild(cbClient, step, config, pctx));

    let pollResult = await ctx.step(`poll`, () => pollBuild(cbClient, buildId));
    while (!TERMINAL_BUILD_STATUSES.has(pollResult.status)) {
      await ctx.wait(`poll-wait`, { seconds: POLL_INTERVAL_SECONDS });
      pollResult = await ctx.step(`poll`, () => pollBuild(cbClient, buildId));
    }

    // Fetch logs and archive to S3 (best-effort)
    try {
      const logsClient = await createCloudWatchLogsClient(
        clients.sts,
        config.accountId,
        config.region,
      );
      const logs = await ctx.step(`logs`, () => fetchBuildLogs(cbClient, logsClient, buildId));
      await writeLogs(pctx, `${project}.${pctx.deployAction}`, logs);
      // Emit build logs to durable execution logger
      if (logs && logs !== "(empty log stream)" && logs !== "(no logs available)") {
        let truncated = logs.length > 16000 ? logs.slice(-16000) : logs;
        // Start on a clean line boundary when truncated
        if (logs.length > 16000) {
          const firstNewline = truncated.indexOf("\n");
          if (firstNewline > 0) truncated = truncated.slice(firstNewline + 1);
        }
        ctx.logger.info(`- [${project}] CodeBuild:\n${truncated}`);
      }
    } catch {
      // best-effort
    }

    if (pollResult.status !== "SUCCEEDED") {
      return {
        status: "failed" as const,
        project,
        target: step.target,
        account_id: config.accountId,
        error: `Build ${pollResult.status}`,
        build_id: buildId,
      };
    }

    if (pctx.deployAction === "apply") {
      await ctx.step(`outputs`, () =>
        writeOutputs(clients.ssm, step, pollResult.exportedVars, buildId, pctx),
      );
    }

    return {
      status: "succeeded" as const,
      project,
      target: step.target,
      account_id: config.accountId,
      build_id: buildId,
    };
  });
}

/**
 * Supervised execution: plan, approval, and apply as sibling contexts within
 * the branch. Each phase is independently checkpointed and observable.
 */
async function executeSupervisedStep(
  step: StepConfig,
  pctx: PipelineContext,
  clients: AWSClients,
  branchCtx: DurableContext,
): Promise<StepResult> {
  const project = step.project;

  // Phase 1: Plan
  const planResult = await branchCtx.runInChildContext(`plan`, async (ctx) => {
    const config: BuildConfig = await ctx.step(`prepare`, () =>
      prepareBuildConfig(clients.ssm, step, pctx.namespace),
    );

    const cbClient = await createCodeBuildClient(
      clients.sts,
      config.accountId,
      config.region,
      config.runner,
    );

    const planPctx = { ...pctx, deployAction: "plan" as const };
    const buildId: string = await ctx.step(`build`, () =>
      startBuild(cbClient, step, config, planPctx),
    );

    let pollResult = await ctx.step(`poll`, () => pollBuild(cbClient, buildId));
    while (!TERMINAL_BUILD_STATUSES.has(pollResult.status)) {
      await ctx.wait(`poll-wait`, { seconds: POLL_INTERVAL_SECONDS });
      pollResult = await ctx.step(`poll`, () => pollBuild(cbClient, buildId));
    }

    // Fetch logs and archive to S3 (best-effort)
    let logs = "";
    try {
      const logsClient = await createCloudWatchLogsClient(
        clients.sts,
        config.accountId,
        config.region,
      );
      logs = await ctx.step(`logs`, () => fetchBuildLogs(cbClient, logsClient, buildId));
      await writeLogs(pctx, `${step.project}.plan`, logs);
      if (logs && logs !== "(empty log stream)" && logs !== "(no logs available)") {
        let truncated = logs.length > 16000 ? logs.slice(-16000) : logs;
        if (logs.length > 16000) {
          const firstNewline = truncated.indexOf("\n");
          if (firstNewline > 0) truncated = truncated.slice(firstNewline + 1);
        }
        ctx.logger.info(`- [${step.project}] CodeBuild (plan):\n${truncated}`);
      }
    } catch {
      // best-effort
    }

    return {
      succeeded: pollResult.status === "SUCCEEDED",
      buildId,
      config,
      logs,
    };
  });

  if (!planResult.succeeded) {
    return {
      status: "failed",
      project,
      target: step.target,
      account_id: planResult.config.accountId,
      error: "Plan build failed",
      build_id: planResult.buildId,
    };
  }

  // Phase 2: Approval (at branch level — visible as sibling to plan/apply)
  branchCtx.logger.info(`⏸ [${project}] awaiting approval`);
  try {
    // Approval currently comes from the durable-execution console, which lists
    // pending callbacks directly from the durable service. We deliberately do
    // NOT persist the callback id to SSM: nothing consumes it yet, and the
    // approval data layer will be redesigned with the future UI. Publishing it
    // (Overwrite:true, never deleted) only left stale "pending" records behind.
    await branchCtx.waitForCallback(`approval`, async (callbackId, _ctx) => {
      branchCtx.logger.info(`[${project}] approval callback registered: ${callbackId}`);
    });
    branchCtx.logger.info(`▶ [${project}] approved, applying`);
  } catch {
    // SendDurableExecutionCallbackFailure throws CallbackError
    branchCtx.logger.info(`✗ [${project}] rejected by approver`);
    return {
      status: "failed",
      project,
      target: step.target,
      account_id: planResult.config.accountId,
      error: "Rejected by approver",
      build_id: planResult.buildId,
    };
  }

  // Phase 3: Apply
  const applyResult = await branchCtx.runInChildContext(`apply`, async (ctx) => {
    const cbClient = await createCodeBuildClient(
      clients.sts,
      planResult.config.accountId,
      planResult.config.region,
      planResult.config.runner,
    );

    const buildId: string = await ctx.step(`build`, () =>
      startBuild(cbClient, step, planResult.config, pctx, [
        { name: "PROPELLER_SAVED_PLAN", value: "1" },
      ]),
    );

    let pollResult = await ctx.step(`poll`, () => pollBuild(cbClient, buildId));
    while (!TERMINAL_BUILD_STATUSES.has(pollResult.status)) {
      await ctx.wait(`poll-wait`, { seconds: POLL_INTERVAL_SECONDS });
      pollResult = await ctx.step(`poll`, () => pollBuild(cbClient, buildId));
    }

    // Fetch and archive apply logs (best-effort)
    try {
      const logsClient = await createCloudWatchLogsClient(
        clients.sts,
        planResult.config.accountId,
        planResult.config.region,
      );
      const logs = await ctx.step(`logs`, () => fetchBuildLogs(cbClient, logsClient, buildId));
      await writeLogs(pctx, `${step.project}.apply`, logs);
      if (logs && logs !== "(empty log stream)" && logs !== "(no logs available)") {
        let truncated = logs.length > 16000 ? logs.slice(-16000) : logs;
        if (logs.length > 16000) {
          const firstNewline = truncated.indexOf("\n");
          if (firstNewline > 0) truncated = truncated.slice(firstNewline + 1);
        }
        ctx.logger.info(`- [${step.project}] CodeBuild (apply):\n${truncated}`);
      }
    } catch {
      // best-effort
    }

    if (pollResult.status !== "SUCCEEDED") {
      return {
        succeeded: false as const,
        buildId,
        error: `Apply build ${pollResult.status}`,
      };
    }

    await ctx.step(`outputs`, () =>
      writeOutputs(clients.ssm, step, pollResult.exportedVars, buildId, pctx),
    );

    return { succeeded: true as const, buildId };
  });

  if (!applyResult.succeeded) {
    return {
      status: "failed",
      project,
      target: step.target,
      account_id: planResult.config.accountId,
      error: applyResult.error,
      build_id: applyResult.buildId,
    };
  }

  return {
    status: "succeeded",
    project,
    target: step.target,
    account_id: planResult.config.accountId,
    build_id: applyResult.buildId,
  };
}

function requiresApproval(step: StepConfig, pctx: PipelineContext): boolean {
  return pctx.supervised || step.approval === "required";
}
