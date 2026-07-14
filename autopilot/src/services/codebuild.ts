/**
 * CodeBuild operations for the Propeller Autopilot.
 *
 * Handles starting builds with the correct environment, polling for
 * completion, and fetching build logs from CloudWatch.
 */

import type { CloudWatchLogsClient } from "@aws-sdk/client-cloudwatch-logs";
import { GetLogEventsCommand } from "@aws-sdk/client-cloudwatch-logs";
import type { CodeBuildClient } from "@aws-sdk/client-codebuild";
import { BatchGetBuildsCommand, StartBuildCommand } from "@aws-sdk/client-codebuild";
import { BUILDSPEC } from "../constants.js";
import type {
  BuildConfig,
  BuildPollResult,
  BuildStatus,
  PipelineContext,
  StepConfig,
} from "../types.js";

export async function startBuild(
  client: CodeBuildClient,
  step: StepConfig,
  config: BuildConfig,
  pctx: PipelineContext,
): Promise<string> {
  const s3Parts = pctx.bundleS3Uri.replace("s3://", "").split("/", 1);
  const s3Location = `${s3Parts[0]}/${pctx.bundleS3Uri.replace("s3://", "").slice(s3Parts[0]!.length + 1)}`;

  const envVars = [
    { name: "PROJECT_NAME", value: step.project, type: "PLAINTEXT" as const },
    { name: "PROPELLER_NAMESPACE", value: pctx.namespace, type: "PLAINTEXT" as const },
    { name: "DEPLOY_ACTION", value: pctx.deployAction, type: "PLAINTEXT" as const },
    { name: "AWS_ACCOUNT_ID", value: config.accountId, type: "PLAINTEXT" as const },
    { name: "AWS_REGION", value: config.region, type: "PLAINTEXT" as const },
    { name: "PROPELLER_EXECUTION_ID", value: pctx.executionId, type: "PLAINTEXT" as const },
    {
      name: "PROPELLER_FRAMEWORK_TAGS_JSON",
      value: JSON.stringify(step.propeller_tags ?? {}),
      type: "PLAINTEXT" as const,
    },
    {
      name: "PROPELLER_CONSUMER_TAGS_JSON",
      value: JSON.stringify(pctx.consumerTags),
      type: "PLAINTEXT" as const,
    },
  ];

  for (const [varName, value] of Object.entries(config.inputs)) {
    envVars.push({
      name: `PROPELLER_INPUT_${varName}`,
      value,
      type: "PLAINTEXT" as const,
    });
  }

  const buildParams: Record<string, unknown> = {
    projectName: config.codebuildProject,
    sourceTypeOverride: "S3",
    sourceLocationOverride: s3Location,
    buildspecOverride: BUILDSPEC,
    environmentVariablesOverride: envVars,
  };

  if (step.timeout) {
    buildParams.timeoutInMinutesOverride = step.timeout;
  }

  const resp = await client.send(new StartBuildCommand(buildParams as any));
  return resp.build!.id!;
}

export async function pollBuild(
  client: CodeBuildClient,
  buildId: string,
): Promise<BuildPollResult> {
  const resp = await client.send(new BatchGetBuildsCommand({ ids: [buildId] }));
  const build = resp.builds![0]!;
  return {
    status: build.buildStatus as BuildStatus,
    exportedVars: (build.exportedEnvironmentVariables ?? []).map((v) => ({
      name: v.name ?? "",
      value: v.value ?? "",
    })),
  };
}

export async function fetchBuildLogs(
  codebuildClient: CodeBuildClient,
  logsClient: CloudWatchLogsClient,
  buildId: string,
): Promise<string> {
  const resp = await codebuildClient.send(new BatchGetBuildsCommand({ ids: [buildId] }));
  const build = resp.builds![0]!;
  const logsInfo = build.logs;

  const groupName = logsInfo?.groupName;
  const streamName = logsInfo?.streamName;

  if (!groupName || !streamName) {
    return "(no logs available)";
  }

  const lines: string[] = [];
  let nextToken: string | undefined;

  while (true) {
    const logResp = await logsClient.send(
      new GetLogEventsCommand({
        logGroupName: groupName,
        logStreamName: streamName,
        startFromHead: true,
        nextToken,
      }),
    );

    const events = logResp.events ?? [];
    if (events.length === 0) break;

    for (const event of events) {
      if (event.message) lines.push(event.message);
    }

    const newToken = logResp.nextForwardToken;
    if (newToken === nextToken) break;
    nextToken = newToken;
  }

  return lines.length > 0 ? lines.join("\n") : "(empty log stream)";
}
