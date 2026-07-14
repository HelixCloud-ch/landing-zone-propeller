/**
 * AWS client factory with injectable overrides for testing.
 *
 * All AWS SDK clients are created through this module, enabling
 * full substitution in tests without mocking module internals.
 */

import { CloudWatchLogsClient } from "@aws-sdk/client-cloudwatch-logs";
import { CodeBuildClient } from "@aws-sdk/client-codebuild";
import { SSMClient } from "@aws-sdk/client-ssm";
import { AssumeRoleCommand, STSClient } from "@aws-sdk/client-sts";
import { RUN_ROLE_NAME } from "../constants.js";

export interface AWSClients {
  ssm: SSMClient;
  sts: STSClient;
}

export function createClients(overrides?: Partial<AWSClients>): AWSClients {
  return {
    ssm: overrides?.ssm ?? new SSMClient({ maxAttempts: 5, retryMode: "adaptive" }),
    sts: overrides?.sts ?? new STSClient({}),
  };
}

export async function createCodeBuildClient(
  stsClient: STSClient,
  accountId: string,
  region: string,
  runner?: string,
): Promise<CodeBuildClient> {
  const runRole = runner ? `${runner}-run-role` : RUN_ROLE_NAME;
  const roleArn = `arn:aws:iam::${accountId}:role/${runRole}`;

  const resp = await stsClient.send(
    new AssumeRoleCommand({
      RoleArn: roleArn,
      RoleSessionName: `propeller-${accountId}`,
    }),
  );

  const creds = resp.Credentials!;
  return new CodeBuildClient({
    region,
    credentials: {
      accessKeyId: creds.AccessKeyId!,
      secretAccessKey: creds.SecretAccessKey!,
      sessionToken: creds.SessionToken!,
    },
  });
}

export async function createCloudWatchLogsClient(
  stsClient: STSClient,
  accountId: string,
  region: string,
): Promise<CloudWatchLogsClient> {
  const roleArn = `arn:aws:iam::${accountId}:role/${RUN_ROLE_NAME}`;

  const resp = await stsClient.send(
    new AssumeRoleCommand({
      RoleArn: roleArn,
      RoleSessionName: `propeller-logs-${accountId}`,
    }),
  );

  const creds = resp.Credentials!;
  return new CloudWatchLogsClient({
    region,
    credentials: {
      accessKeyId: creds.AccessKeyId!,
      secretAccessKey: creds.SecretAccessKey!,
      sessionToken: creds.SessionToken!,
    },
  });
}
