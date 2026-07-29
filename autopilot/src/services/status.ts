/**
 * Execution status tracker.
 *
 * Maintains the live execution state and writes it to S3 as status.json.
 * Decoupled from pipeline logic: call emit() at state transitions.
 */

import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import type { PipelineContext } from "../types.js";

export type StepStatus = "pending" | "running" | "succeeded" | "failed" | "skipped";

interface StepState {
  project: string;
  status: StepStatus;
  startedAt?: string;
  completedAt?: string;
}

interface ExecutionState {
  executionId: string;
  namespace: string;
  action: string;
  status: "running" | "succeeded" | "failed";
  startedAt: string;
  completedAt: string | null;
  summary: { succeeded: number; failed: number; skipped: number; pending: number; running: number };
  steps: StepState[];
}

export class StatusTracker {
  private state: ExecutionState;
  private s3: S3Client;
  private bucket: string;
  private key: string;

  constructor(pctx: PipelineContext, projects: string[]) {
    this.s3 = new S3Client({});
    this.bucket = extractBucket(pctx.bundleS3Uri);
    this.key = `executions/${pctx.executionId}/status.json`;
    this.state = {
      executionId: pctx.executionId,
      namespace: pctx.namespace,
      action: pctx.deployAction,
      status: "running",
      startedAt: new Date().toISOString(),
      completedAt: null,
      summary: { succeeded: 0, failed: 0, skipped: 0, pending: projects.length, running: 0 },
      steps: projects.map((p) => ({ project: p, status: "pending" as StepStatus })),
    };
  }

  async start(): Promise<void> {
    await this.write();
  }

  async stepStarted(project: string): Promise<void> {
    const step = this.state.steps.find((s) => s.project === project);
    if (!step) return;
    step.status = "running";
    step.startedAt = new Date().toISOString();
    this.recount();
    await this.write();
  }

  async stepCompleted(project: string, status: "succeeded" | "failed" | "skipped"): Promise<void> {
    const step = this.state.steps.find((s) => s.project === project);
    if (!step) return;
    step.status = status;
    step.completedAt = new Date().toISOString();
    this.recount();
    await this.write();
  }

  async complete(status: "succeeded" | "failed"): Promise<void> {
    this.state.status = status;
    this.state.completedAt = new Date().toISOString();
    await this.write();
  }

  private recount(): void {
    const steps = this.state.steps;
    this.state.summary = {
      succeeded: steps.filter((s) => s.status === "succeeded").length,
      failed: steps.filter((s) => s.status === "failed").length,
      skipped: steps.filter((s) => s.status === "skipped").length,
      pending: steps.filter((s) => s.status === "pending").length,
      running: steps.filter((s) => s.status === "running").length,
    };
  }

  private async write(): Promise<void> {
    try {
      await this.s3.send(
        new PutObjectCommand({
          Bucket: this.bucket,
          Key: this.key,
          Body: JSON.stringify(this.state, null, 2),
          ContentType: "application/json",
        }),
      );
    } catch {
      // Best-effort: don't fail the pipeline if status write fails
    }
  }
}

function extractBucket(s3Uri: string): string {
  return s3Uri.replace("s3://", "").split("/")[0]!;
}
