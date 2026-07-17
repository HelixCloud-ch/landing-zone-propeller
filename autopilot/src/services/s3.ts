/**
 * S3 operations for the Propeller Autopilot.
 *
 * Handles log archival and active bundle promotion.
 */

import { CopyObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import type { PipelineContext } from "../types.js";

/** Extract bucket name from an s3:// URI. */
export function extractBucket(s3Uri: string): string {
  const bucket = s3Uri.replace("s3://", "").split("/")[0];
  if (!bucket) throw new Error(`Invalid S3 URI: ${s3Uri}`);
  return bucket;
}

/** Write build logs to S3 in the operations account (best-effort, swallows errors). */
export async function writeLogs(pctx: PipelineContext, label: string, logs: string): Promise<void> {
  if (!logs || !pctx.executionId) return;
  try {
    const bucket = extractBucket(pctx.bundleS3Uri);
    const key = `propeller-logs/${pctx.executionId}/${label}.log`;
    const s3 = new S3Client({});
    await s3.send(
      new PutObjectCommand({
        Bucket: bucket,
        Key: key,
        Body: logs,
        ContentType: "text/plain",
      }),
    );
  } catch {
    // best-effort
  }
}

/** Copy the deployed bundle to the active/ prefix so sleep/wake can find it. */
export async function promoteActiveBundle(pctx: PipelineContext): Promise<void> {
  const copySource = pctx.bundleS3Uri.replace("s3://", "");
  const bucket = extractBucket(pctx.bundleS3Uri);
  const activeKey = `active/${pctx.namespace}/bundle.zip`;

  const s3 = new S3Client({});
  await s3.send(
    new CopyObjectCommand({
      Bucket: bucket,
      CopySource: copySource,
      Key: activeKey,
      MetadataDirective: "REPLACE",
      Metadata: {
        "bundle-s3-uri": pctx.bundleS3Uri,
        "git-sha": pctx.gitSha,
        "propeller-version": pctx.propellerVersion,
        "execution-id": pctx.executionId,
        "deploy-action": pctx.deployAction,
        "promoted-at": new Date().toISOString(),
      },
    }),
  );
}
