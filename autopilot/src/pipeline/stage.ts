/**
 * Stage execution engine for the Propeller Autopilot.
 *
 * Handles wave-based parallel execution within stages, respecting
 * the DAG ordering and propagating failures to dependents.
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

    const branches = ready.map((project) => async (branchCtx: DurableContext) => {
      return await branchCtx.runInChildContext(project, async (childCtx) => {
        return await executeStep(stepMap.get(project)!, pctx, clients, childCtx);
      });
    });

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

export async function executeStep(
  step: StepConfig,
  pctx: PipelineContext,
  clients: AWSClients,
  durableCtx: DurableContext,
): Promise<StepResult> {
  const project = step.project;

  try {
    const config: BuildConfig = await durableCtx.step(`prepare`, () =>
      prepareBuildConfig(clients.ssm, step, pctx.namespace),
    );

    const cbClient = await durableCtx.step(`assume-role`, () =>
      createCodeBuildClient(clients.sts, config.accountId, config.region, config.runner),
    );

    // If approval is needed, first build runs as "plan"
    const effectivePctx =
      pctx.deployAction === "apply" && requiresApproval(step, pctx)
        ? { ...pctx, deployAction: "plan" as const }
        : pctx;

    const buildId: string = await durableCtx.step(`start-build`, () =>
      startBuild(cbClient, step, config, effectivePctx),
    );

    let pollResult = await durableCtx.step(`poll`, () => pollBuild(cbClient, buildId));

    while (!TERMINAL_BUILD_STATUSES.has(pollResult.status)) {
      await durableCtx.wait(`poll-wait`, { seconds: POLL_INTERVAL_SECONDS });
      pollResult = await durableCtx.step(`poll`, () => pollBuild(cbClient, buildId));
    }

    // Fetch logs
    let logs = "";
    try {
      const logsClient = await durableCtx.step(`logs-client`, () =>
        createCloudWatchLogsClient(clients.sts, config.accountId, config.region),
      );
      logs = await durableCtx.step(`logs`, () => fetchBuildLogs(cbClient, logsClient, buildId));
    } catch {
      // Log fetching is best-effort
    }

    if (pollResult.status !== "SUCCEEDED") {
      return {
        status: "failed",
        project,
        target: step.target,
        account_id: config.accountId,
        error: `Build ${pollResult.status}`,
        build_id: buildId,
        logs,
      };
    }

    // Approval gate: if supervised or step requires approval, run plan first then wait
    if (pctx.deployAction === "apply" && requiresApproval(step, pctx)) {
      // The build above was a plan — now wait for human approval via callback
      const callbackResult = await durableCtx.waitForCallback(
        `approve:${project}`,
        async (callbackId, _ctx) => {
          // Store the callback ID in SSM so the approval UI can invoke it
          await clients.ssm.send(
            new PutParameterCommand({
              Name: `/propeller/${pctx.namespace}/approvals/${project}`,
              Value: JSON.stringify({
                callbackId,
                project,
                executionId: pctx.executionId,
                buildId,
                requestedAt: new Date().toISOString(),
              }),
              Type: "String",
              Overwrite: true,
            }),
          );
        },
      );
      const approved = callbackResult !== "rejected";

      if (!approved) {
        return {
          status: "failed",
          project,
          target: step.target,
          account_id: config.accountId,
          error: "Rejected by approver",
          build_id: buildId,
          logs,
        };
      }

      // Run the actual apply build
      const applyBuildId: string = await durableCtx.step(`apply-build`, () =>
        startBuild(cbClient, step, config, pctx),
      );

      let applyPoll = await durableCtx.step(`apply-poll`, () => pollBuild(cbClient, applyBuildId));
      while (!TERMINAL_BUILD_STATUSES.has(applyPoll.status)) {
        await durableCtx.wait(`apply-poll-wait`, { seconds: POLL_INTERVAL_SECONDS });
        applyPoll = await durableCtx.step(`apply-poll`, () => pollBuild(cbClient, applyBuildId));
      }

      if (applyPoll.status !== "SUCCEEDED") {
        return {
          status: "failed",
          project,
          target: step.target,
          account_id: config.accountId,
          error: `Apply build ${applyPoll.status}`,
          build_id: applyBuildId,
        };
      }

      await durableCtx.step(`outputs`, () =>
        writeOutputs(clients.ssm, step, applyPoll.exportedVars, applyBuildId, pctx),
      );

      return {
        status: "succeeded",
        project,
        target: step.target,
        account_id: config.accountId,
        build_id: applyBuildId,
        logs,
      };
    }

    if (pctx.deployAction === "apply") {
      await durableCtx.step(`outputs`, () =>
        writeOutputs(clients.ssm, step, pollResult.exportedVars, buildId, pctx),
      );
    }

    return {
      status: "succeeded",
      project,
      target: step.target,
      account_id: config.accountId,
      build_id: buildId,
      logs,
    };
  } catch (err: unknown) {
    return {
      status: "failed",
      project,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

function requiresApproval(step: StepConfig, pctx: PipelineContext): boolean {
  return pctx.supervised || step.approval === "required";
}
