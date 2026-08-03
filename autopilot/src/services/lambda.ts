/**
 * Lambda service operations for the Propeller Autopilot.
 *
 * Handles concurrent execution checks using the Durable Execution API.
 */

import { LambdaClient, ListDurableExecutionsByFunctionCommand } from "@aws-sdk/client-lambda";

declare const process: { env: Record<string, string | undefined> };

/**
 * Check if another durable execution for the same namespace is already running.
 * Returns the conflicting execution name, or null if none found.
 */
export async function checkConcurrentExecution(
  namespace: string,
  currentArn: string,
): Promise<string | null> {
  try {
    const lambda = new LambdaClient({});
    const functionName = process.env.AWS_LAMBDA_FUNCTION_NAME;
    if (!functionName) return null;

    const resp = await lambda.send(
      new ListDurableExecutionsByFunctionCommand({
        FunctionName: functionName,
        Statuses: ["RUNNING"],
        MaxItems: 100,
      }),
    );

    const executions = resp.DurableExecutions ?? [];
    const conflict = executions.find(
      (e) =>
        e.DurableExecutionName?.startsWith(`${namespace}__`) &&
        e.DurableExecutionArn !== currentArn,
    );

    return conflict?.DurableExecutionName ?? null;
  } catch (err: unknown) {
    (globalThis as any).console?.warn?.(
      "[concurrent-check] Failed:",
      err instanceof Error ? err.message : String(err),
    );
    return null;
  }
}
