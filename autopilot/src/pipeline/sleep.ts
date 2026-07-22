/**
 * Sleep/wake dispatch logic for the Propeller Autopilot.
 *
 * Uses preset-based mode resolution: projects listed in the active preset
 * participate in sleep/wake, others are skipped. Each participating project
 * receives PROPELLER_SLEEP_MODE as an env var and dispatches via its justfile.
 */

import type { DurableContext } from "@aws/durable-execution-sdk-js";
import { POLL_INTERVAL_SECONDS, TERMINAL_BUILD_STATUSES } from "../constants.js";
import type { AWSClients } from "../services/aws.js";
import { createCodeBuildClient } from "../services/aws.js";
import { pollBuild, startBuild } from "../services/codebuild.js";
import { writeLogs } from "../services/s3.js";
import { prepareBuildConfig, writeOutputs } from "../services/ssm.js";
import { createCloudWatchLogsClient } from "../services/aws.js";
import { fetchBuildLogs } from "../services/codebuild.js";
import type {
  PipelineContext,
  Stage,
  StepConfig,
  StepResult,
} from "../types.js";
import { buildDag, findDependents, findReady, reverseDag } from "./dag.js";

export async function runStageSleepWake(
  stage: Stage,
  pctx: PipelineContext,
  clients: AWSClients,
  durableCtx: DurableContext,
): Promise<StepResult[]> {
  const isWake = pctx.deployAction === "wake";
  const steps = stage.steps;
  const stepMap = new Map(steps.map((s) => [s.project, s]));
  const rawDag = buildDag(steps);
  // Sleep: reverse dependency order (tear down dependents first)
  // Wake: normal dependency order (bring up dependencies first)
  const dag = isWake ? rawDag : reverseDag(rawDag);

  const completed = new Set<string>();
  const failed = new Set<string>();
  const skipped = new Set<string>();
  const results = new Map<string, StepResult>();
  let waveNum = 0;

  while (completed.size + failed.size + skipped.size < dag.size) {
    const ready = findReady(dag, completed, failed, skipped);
    if (ready.length === 0) break;

    const branches: Array<(ctx: DurableContext) => Promise<StepResult>> = [];

    for (const project of ready) {
      const step = stepMap.get(project)!;
      const mode = resolveSleepMode(step, pctx);

      if (!mode) {
        // Project not in preset — does not participate
        skipped.add(project);
        results.set(project, {
          status: "skipped",
          project,
          error: "not in sleep preset",
        });
      } else {
        const capturedStep = step;
        const capturedMode = mode;
        branches.push(async (branchCtx: DurableContext) => {
          return await branchCtx.runInChildContext(project, async (childCtx) => {
            return await executeSleepStep(capturedStep, pctx, clients, capturedMode, childCtx);
          });
        });
      }
    }

    if (branches.length === 0) continue;

    const batchResults = await durableCtx.parallel(`sleep-wave:${stage.name}:${waveNum}`, branches);
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
 * Resolve the sleep mode for a project.
 * Returns the mode string if the project participates, or null if it doesn't.
 *
 * Resolution: pctx.sleepModes (from preset) → legacy step.sleep_config → null
 */
function resolveSleepMode(step: StepConfig, pctx: PipelineContext): string | null {
  // New path: preset-based modes
  const presetMode = pctx.sleepModes[step.project];
  if (presetMode) return presetMode;

  // Legacy path: step.sleep + step.sleep_config (backwards compat)
  if (step.sleep && step.sleep_config) {
    if (step.sleep_config.action === "skip") return null;
    return step.sleep_config.action === "destroy" ? "destroy" : "command";
  }

  return null;
}

/**
 * Execute a sleep/wake step by running it through the standard CodeBuild
 * pipeline with PROPELLER_SLEEP_MODE set. The project's justfile handles
 * the actual sleep/wake logic based on the mode.
 */
async function executeSleepStep(
  step: StepConfig,
  pctx: PipelineContext,
  clients: AWSClients,
  mode: string,
  ctx: DurableContext,
): Promise<StepResult> {
  const project = step.project;

  try {
    return await ctx.runInChildContext(`${pctx.deployAction}`, async (childCtx) => {
      const config = await childCtx.step(`prepare`, () =>
        prepareBuildConfig(clients.ssm, step, pctx.namespace),
      );

      const cbClient = await createCodeBuildClient(
        clients.sts,
        config.accountId,
        config.region,
        config.runner,
      );

      const extraEnvVars = [
        { name: "PROPELLER_SLEEP_MODE", value: mode },
      ];

      const buildId: string = await childCtx.step(`build`, () =>
        startBuild(cbClient, step, config, pctx, extraEnvVars),
      );

      let pollResult = await childCtx.step(`poll`, () => pollBuild(cbClient, buildId));
      while (!TERMINAL_BUILD_STATUSES.has(pollResult.status)) {
        await childCtx.wait(`poll-wait`, { seconds: POLL_INTERVAL_SECONDS });
        pollResult = await childCtx.step(`poll`, () => pollBuild(cbClient, buildId));
      }

      // Fetch logs (best-effort)
      try {
        const logsClient = await createCloudWatchLogsClient(
          clients.sts,
          config.accountId,
          config.region,
        );
        const logs = await childCtx.step(`logs`, () =>
          fetchBuildLogs(cbClient, logsClient, buildId),
        );
        await writeLogs(pctx, `${project}.${pctx.deployAction}`, logs);
      } catch {
        // best-effort
      }

      if (pollResult.status !== "SUCCEEDED") {
        return {
          status: "failed" as const,
          project,
          target: step.target,
          account_id: config.accountId,
          error: `${pctx.deployAction} (mode=${mode}) ${pollResult.status}`,
          build_id: buildId,
        };
      }

      // Write outputs if the sleep/wake recipe produced any (e.g. snapshot ID)
      if (pollResult.exportedVars.length > 0) {
        await childCtx.step(`outputs`, () =>
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
  } catch (err: unknown) {
    return {
      status: "failed",
      project,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}
