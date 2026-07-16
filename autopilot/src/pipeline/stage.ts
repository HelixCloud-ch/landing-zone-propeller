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
 *       apply (RunInChildContext)     ← only when approval required
 */

import type { DurableContext } from "@aws/durable-execution-sdk-js";
import { PutParameterCommand } from "@aws-sdk/client-ssm";
import { POLL_INTERVAL_SECONDS, TERMINAL_BUILD_STATUSES } from "../constants.js";
import type { AWSClients } from "../services/aws.js";
import { createCloudWatchLogsClient, createCodeBuildClient } from "../services/aws.js";
import { fetchBuildLogs, pollBuild, startBuild } from "../services/codebuild.js";
import { prepareBuildConfig, writeOutputs } from "../services/ssm.js";
import type { BuildConfig, PipelineContext, Stage, StepConfig, StepResult } from "../types.js";
import { buildDag, findDependents, findReady } from "./dag.js";

export async function runStage(
  stage: Stage,
  pctx: PipelineContext,
  clients: AWSClients,
  durableCtx: DurableContext,
): Promise<StepResult[]> {
  const steps = stage.steps;
  const stepMap = new Map(steps.map((s) => [s.project, s]));
  const dag = buildDag(steps);

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
        const step = stepMap.get(project)!;
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

  try {
    if (pctx.deployAction === "apply" && requiresApproval(step, pctx)) {
      return await executeSupervisedStep(step, pctx, clients, branchCtx);
    }
    return await executeDirectStep(step, pctx, clients, branchCtx);
  } catch (err: unknown) {
    return {
      status: "failed",
      project,
      error: err instanceof Error ? err.message : String(err),
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

    const buildId: string = await ctx.step(`build`, () =>
      startBuild(cbClient, step, config, pctx),
    );

    let pollResult = await ctx.step(`poll`, () => pollBuild(cbClient, buildId));
    while (!TERMINAL_BUILD_STATUSES.has(pollResult.status)) {
      await ctx.wait(`poll-wait`, { seconds: POLL_INTERVAL_SECONDS });
      pollResult = await ctx.step(`poll`, () => pollBuild(cbClient, buildId));
    }

    // Fetch logs (best-effort)
    let logs = "";
    try {
      const logsClient = await createCloudWatchLogsClient(
        clients.sts,
        config.accountId,
        config.region,
      );
      logs = await ctx.step(`logs`, () => fetchBuildLogs(cbClient, logsClient, buildId));
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
        logs,
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
      logs,
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

    // Fetch logs (best-effort)
    let logs = "";
    try {
      const logsClient = await createCloudWatchLogsClient(
        clients.sts,
        config.accountId,
        config.region,
      );
      logs = await ctx.step(`logs`, () => fetchBuildLogs(cbClient, logsClient, buildId));
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
      logs: planResult.logs,
    };
  }

  // Phase 2: Approval (at branch level — visible as sibling to plan/apply)
  try {
    await branchCtx.waitForCallback(
      `approval`,
      async (callbackId, _ctx) => {
        await clients.ssm.send(
          new PutParameterCommand({
            Name: `/propeller/${pctx.namespace}/approvals/${project}`,
            Value: JSON.stringify({
              callbackId,
              project,
              executionId: pctx.executionId,
              buildId: planResult.buildId,
              requestedAt: new Date().toISOString(),
            }),
            Type: "String",
            Overwrite: true,
          }),
        );
      },
    );
  } catch {
    // SendDurableExecutionCallbackFailure throws CallbackError
    return {
      status: "failed",
      project,
      target: step.target,
      account_id: planResult.config.accountId,
      error: "Rejected by approver",
      build_id: planResult.buildId,
      logs: planResult.logs,
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
    logs: planResult.logs,
  };
}

function requiresApproval(step: StepConfig, pctx: PipelineContext): boolean {
  return pctx.supervised || step.approval === "required";
}
