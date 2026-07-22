/**
 * SSM Parameter Store operations for the Propeller Autopilot.
 *
 * Handles reading inputs (resolving cross-project references),
 * writing outputs (individual parameters + project blobs), and
 * managing pipeline state.
 */

import type { SSMClient } from "@aws-sdk/client-ssm";
import { GetParameterCommand, PutParameterCommand } from "@aws-sdk/client-ssm";

declare const process: { env: Record<string, string | undefined> };

import { ACCOUNTS_SSM_PREFIX, EMPTY_SENTINEL } from "../constants.js";
import type { BuildConfig, PipelineContext, ProjectBlob, StepConfig } from "../types.js";

export async function getParameter(client: SSMClient, name: string): Promise<string> {
  const resp = await client.send(new GetParameterCommand({ Name: name }));
  return resp.Parameter!.Value!;
}

export async function getParameterOptional(
  client: SSMClient,
  name: string,
): Promise<string | null> {
  try {
    const resp = await client.send(new GetParameterCommand({ Name: name }));
    return resp.Parameter!.Value!;
  } catch (err: unknown) {
    if (err instanceof Error && err.name === "ParameterNotFound") {
      return null;
    }
    throw err;
  }
}

export async function resolveInputs(
  client: SSMClient,
  step: StepConfig,
  _namespace: string,
): Promise<Record<string, string>> {
  const inputs: Record<string, string> = {};
  const blobCache: Map<string, Record<string, string>> = new Map();

  for (const inp of step.inputs ?? []) {
    if (inp.field) {
      const key = inp.key;
      if (!blobCache.has(key)) {
        const raw = await getParameter(client, key);
        const parsed = JSON.parse(raw) as { outputs: Record<string, string> };
        blobCache.set(key, parsed.outputs);
      }
      const outputs = blobCache.get(key)!;
      inputs[inp.var] = String(outputs[inp.field] ?? "");
    } else {
      const raw = await getParameterOptional(client, inp.key);
      if (raw === null || raw === EMPTY_SENTINEL) {
        inputs[inp.var] = "";
      } else {
        inputs[inp.var] = raw;
      }
    }
  }

  return inputs;
}

export async function prepareBuildConfig(
  client: SSMClient,
  step: StepConfig,
  namespace: string,
): Promise<BuildConfig> {
  const target = step.target ?? "default";
  const prefix = `${ACCOUNTS_SSM_PREFIX}/${target}`;

  const accountId = await getParameter(client, `${prefix}/id`);
  const region =
    (await getParameterOptional(client, `${prefix}/region`)) ??
    process.env.AWS_REGION ??
    "us-east-1";

  const inputs = await resolveInputs(client, step, namespace);

  return {
    accountId,
    region,
    codebuildProject: step.runner ?? "deploy-runner",
    runner: step.runner,
    inputs,
  };
}

export async function writeOutputs(
  client: SSMClient,
  step: StepConfig,
  exportedVars: Array<{ name: string; value: string }>,
  buildId: string,
  pctx: PipelineContext,
): Promise<Record<string, string>> {
  const outputDefs = step.outputs ?? [];

  let outputsJson = "{}";
  for (const v of exportedVars) {
    if (v.name === "PROPELLER_OUTPUTS_JSON") {
      outputsJson = v.value;
      break;
    }
  }

  const outputs = JSON.parse(outputsJson) as Record<string, unknown>;
  const blobOutputs: Record<string, string> = {};
  const written: Record<string, string> = {};

  for (const def of outputDefs) {
    const ref = def.ref;
    const value = outputs[ref];
    if (value === undefined) continue;

    if (def.field) {
      blobOutputs[def.field] = String(value);
    } else {
      const strValue = String(value);
      const ssmValue = strValue === "" ? EMPTY_SENTINEL : strValue;
      await client.send(
        new PutParameterCommand({
          Name: def.key,
          Value: ssmValue,
          Type: "String",
          Overwrite: true,
        }),
      );
      written[ref] = def.key;
    }
  }

  const blobKey = pctx.namespace
    ? `/propeller/${pctx.namespace}/${step.project}`
    : `/propeller/${step.project}`;

  const blobValue: ProjectBlob = {
    outputs: blobOutputs,
    meta: {
      propeller_version: pctx.propellerVersion,
      deployed_at: new Date().toISOString(),
      build_id: buildId,
      git_sha: pctx.gitSha,
    },
  };

  await client.send(
    new PutParameterCommand({
      Name: blobKey,
      Value: JSON.stringify(blobValue),
      Type: "String",
      Overwrite: true,
    }),
  );

  for (const field of Object.keys(blobOutputs)) {
    written[field] = `${blobKey}[${field}]`;
  }

  return written;
}

export async function readProjectBlob(
  client: SSMClient,
  namespace: string,
  project: string,
): Promise<ProjectBlob | null> {
  const key = `/propeller/${namespace}/${project}`;
  const raw = await getParameterOptional(client, key);
  if (raw === null) return null;
  return JSON.parse(raw) as ProjectBlob;
}

export interface PipelineState {
  state: "running" | "sleeping";
  sleep_preset?: string;
}

export async function readPipelineState(
  client: SSMClient,
  namespace: string,
): Promise<PipelineState | null> {
  const raw = await getParameterOptional(client, `/propeller/${namespace}/state`);
  if (raw === null) return null;
  // Support legacy plain string format ("running", "sleeping")
  try {
    return JSON.parse(raw) as PipelineState;
  } catch {
    return { state: raw as "running" | "sleeping" };
  }
}

export async function writePipelineState(
  client: SSMClient,
  namespace: string,
  state: "running" | "sleeping",
  sleepPreset?: string,
): Promise<void> {
  const value: PipelineState = { state };
  if (sleepPreset) value.sleep_preset = sleepPreset;
  await client.send(
    new PutParameterCommand({
      Name: `/propeller/${namespace}/state`,
      Value: JSON.stringify(value),
      Type: "String",
      Overwrite: true,
    }),
  );
}
