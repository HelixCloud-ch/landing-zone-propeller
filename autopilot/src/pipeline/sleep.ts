/**
 * Sleep/wake dispatch logic for the Propeller Autopilot.
 *
 * Handles the three sleep behaviors:
 * - destroy: runs terraform destroy (sleep) / terraform apply (wake)
 * - command: executes a custom shell command via CodeBuild
 * - skip: no-op, project doesn't participate in sleep/wake
 */

import type { DurableContext } from "@aws/durable-execution-sdk-js";
import type { CodeBuildClient } from "@aws-sdk/client-codebuild";
import { StartBuildCommand } from "@aws-sdk/client-codebuild";
import type { SSMClient } from "@aws-sdk/client-ssm";
import {
  ACCOUNTS_SSM_PREFIX,
  POLL_INTERVAL_SECONDS,
  TERMINAL_BUILD_STATUSES,
} from "../constants.js";
import type { AWSClients } from "../services/aws.js";
import { createCodeBuildClient } from "../services/aws.js";
import { pollBuild } from "../services/codebuild.js";
import {
  getParameter,
  getParameterOptional,
  prepareBuildConfig,
  readProjectBlob,
  resolveInputs,
} from "../services/ssm.js";
import type {
  BuildConfig,
  PipelineContext,
  SleepAction,
  Stage,
  StepConfig,
  StepResult,
} from "../types.js";
import { buildDag, findDependents, findReady } from "./dag.js";
import { executeStep } from "./stage.js";

declare const process: { env: Record<string, string | undefined> };

const COMMAND_BUILDSPEC = `version: 0.2
phases:
  build:
    commands:
      - eval "$PROPELLER_SLEEP_COMMAND"
`;

export async function runStageSleepWake(
  stage: Stage,
  pctx: PipelineContext,
  clients: AWSClients,
  durableCtx: DurableContext,
): Promise<StepResult[]> {
  const isWake = pctx.deployAction === "wake";
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

    const branches: Array<(ctx: DurableContext) => Promise<StepResult>> = [];
    const readyProjects: string[] = [];

    for (const project of ready) {
      const step = stepMap.get(project)!;
      const behavior = determineSleepBehavior(step);

      if (behavior === "skip") {
        skipped.add(project);
        results.set(project, {
          status: "skipped",
          project,
          error: "sleep: skip (not participating)",
        });
      } else if (behavior === "destroy") {
        const capturedStep = step;
        branches.push(async (branchCtx: DurableContext) => {
          return await branchCtx.runInChildContext(project, async (childCtx) => {
            return await executeSleepDestroy(capturedStep, pctx, clients, isWake, childCtx);
          });
        });
        readyProjects.push(project);
      } else if (behavior === "command") {
        const capturedStep = step;
        branches.push(async (branchCtx: DurableContext) => {
          return await branchCtx.runInChildContext(project, async (childCtx) => {
            return await executeSleepCommand(capturedStep, pctx, clients, isWake, childCtx);
          });
        });
        readyProjects.push(project);
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

export function determineSleepBehavior(step: StepConfig): SleepAction {
  if (!step.sleep) return "skip";
  if (!step.sleep_config) return "skip";
  return step.sleep_config.action ?? "skip";
}

export async function executeSleepDestroy(
  step: StepConfig,
  pctx: PipelineContext,
  clients: AWSClients,
  isWake: boolean,
  durableCtx: DurableContext,
): Promise<StepResult> {
  const overrideAction = isWake ? "apply" : "destroy";
  const overridePctx: PipelineContext = {
    ...pctx,
    deployAction: overrideAction,
  };

  // Apply sleep_config timeout if step doesn't have one
  let effectiveStep = step;
  if (step.sleep_config?.timeout && !step.timeout) {
    effectiveStep = { ...step, timeout: step.sleep_config.timeout };
  }

  return executeStep(effectiveStep, overridePctx, clients, durableCtx);
}

export async function executeSleepCommand(
  step: StepConfig,
  pctx: PipelineContext,
  clients: AWSClients,
  isWake: boolean,
  durableCtx: DurableContext,
): Promise<StepResult> {
  const project = step.project;
  const sleepConfig = step.sleep_config!;
  const rawCommand = isWake ? (sleepConfig.wake_command ?? "") : (sleepConfig.command ?? "");

  try {
    const resolvedCmd = await durableCtx.step(`cmd-resolve:${project}`, () =>
      resolveCommandVars(rawCommand, step, pctx, clients.ssm),
    );

    const config: BuildConfig = await durableCtx.step(`cmd-prepare:${project}`, () =>
      prepareBuildConfig(clients.ssm, step, pctx.namespace),
    );

    const cbClient = await durableCtx.step(`cmd-assume:${project}`, () =>
      createCodeBuildClient(clients.sts, config.accountId, config.region, config.runner),
    );

    const s3Parts = pctx.bundleS3Uri.replace("s3://", "").split("/", 1);
    const s3Location = `${s3Parts[0]}/${pctx.bundleS3Uri.replace("s3://", "").slice(s3Parts[0]!.length + 1)}`;

    const buildId: string = await durableCtx.step(`cmd-start:${project}`, () =>
      startCommandBuild(cbClient, project, pctx, config, resolvedCmd, s3Location),
    );

    let pollResult = await durableCtx.step(`cmd-poll:${project}`, () =>
      pollBuild(cbClient, buildId),
    );

    while (!TERMINAL_BUILD_STATUSES.has(pollResult.status)) {
      await durableCtx.wait(`cmd-poll-wait:${project}`, { seconds: POLL_INTERVAL_SECONDS });
      pollResult = await durableCtx.step(`cmd-poll:${project}`, () => pollBuild(cbClient, buildId));
    }

    if (pollResult.status !== "SUCCEEDED") {
      const actionLabel = isWake ? "wake" : "sleep";
      return {
        status: "failed",
        project,
        error: `${actionLabel} command ${pollResult.status}`,
        build_id: buildId,
      };
    }

    return {
      status: "succeeded",
      project,
      build_id: buildId,
    };
  } catch (err: unknown) {
    return {
      status: "failed",
      project,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

async function startCommandBuild(
  cbClient: CodeBuildClient,
  project: string,
  pctx: PipelineContext,
  config: BuildConfig,
  resolvedCmd: string,
  s3Location: string,
): Promise<string> {
  const envVars = [
    { name: "PROJECT_NAME", value: project, type: "PLAINTEXT" as const },
    { name: "PROPELLER_NAMESPACE", value: pctx.namespace, type: "PLAINTEXT" as const },
    { name: "AWS_ACCOUNT_ID", value: config.accountId, type: "PLAINTEXT" as const },
    { name: "AWS_REGION", value: config.region, type: "PLAINTEXT" as const },
    { name: "PROPELLER_SLEEP_COMMAND", value: resolvedCmd, type: "PLAINTEXT" as const },
  ];

  const resp = await cbClient.send(
    new StartBuildCommand({
      projectName: config.codebuildProject,
      sourceTypeOverride: "S3",
      sourceLocationOverride: s3Location,
      buildspecOverride: COMMAND_BUILDSPEC,
      environmentVariablesOverride: envVars,
    }),
  );

  return resp.build!.id!;
}

export async function resolveCommandVars(
  command: string,
  step: StepConfig,
  pctx: PipelineContext,
  ssmClient: SSMClient,
): Promise<string> {
  const target = step.target ?? "default";
  const prefix = `${ACCOUNTS_SSM_PREFIX}/${target}`;
  const accountId = await getParameter(ssmClient, `${prefix}/id`);
  const region =
    (await getParameterOptional(ssmClient, `${prefix}/region`)) ??
    process.env.AWS_REGION ??
    "us-east-1";

  let result = command;
  result = result.replace(/\$\{AWS_REGION\}/g, region);
  result = result.replace(/\$\{AWS_ACCOUNT_ID\}/g, accountId);
  result = result.replace(/\$\{PROPELLER_NAMESPACE\}/g, pctx.namespace);
  result = result.replace(/\$\{PROJECT_NAME\}/g, step.project);

  // Resolve ${INPUT_*} from step inputs
  const config = await prepareBuildConfig(ssmClient, step, pctx.namespace);
  for (const [varName, value] of Object.entries(config.inputs)) {
    result = result.replace(new RegExp(`\\$\\{INPUT_${varName}\\}`, "g"), String(value));
  }

  // Resolve ${TF_OUTPUT_*} from the project's SSM blob
  if (result.includes("${TF_OUTPUT_")) {
    const blob = await readProjectBlob(ssmClient, pctx.namespace, step.project);
    if (blob) {
      const outputs = blob.outputs;
      const matches = result.matchAll(/\$\{TF_OUTPUT_(\w+)\}/g);
      for (const match of matches) {
        const varName = match[1]!;
        const value = outputs[varName] ?? "";
        result = result.replace(match[0], String(value));
      }
    }
  }

  return result;
}
