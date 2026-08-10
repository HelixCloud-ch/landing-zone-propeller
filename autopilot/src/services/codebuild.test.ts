import type { CodeBuildClient } from "@aws-sdk/client-codebuild";
import { describe, expect, it, vi } from "vitest";
import type { BuildConfig, PipelineContext, StepConfig } from "../types.js";
import { startBuild } from "./codebuild.js";

/** Capture the StartBuild input each call receives. */
function mockCodeBuild() {
  const inputs: Array<Record<string, any>> = [];
  const send = vi.fn(async (command: any) => {
    inputs.push(command.input);
    return { build: { id: "build-1" } };
  });
  return { client: { send } as unknown as CodeBuildClient, inputs };
}

const config: BuildConfig = {
  accountId: "111111111111",
  region: "eu-central-2",
  codebuildProject: "deploy-runner",
  inputs: {},
};

function ctx(overrides: Partial<PipelineContext> = {}): PipelineContext {
  return {
    bundleS3Uri: "s3://bucket/bundles/ns/abc.zip",
    deployAction: "apply",
    namespace: "ns",
    propellerVersion: "v2.3.0",
    gitSha: "sha",
    consumerTags: {},
    executionId: "exec-1",
    supervised: false,
    sleepProjects: {},
    ...overrides,
  };
}

function step(overrides: Partial<StepConfig> = {}): StepConfig {
  return { project: "p", inputs: [], outputs: [], ...overrides };
}

describe("startBuild codebuild overrides", () => {
  it("emits no overrides when nothing is configured", async () => {
    const { client, inputs } = mockCodeBuild();
    await startBuild(client, step(), config, ctx());
    const p = inputs[0]!;
    expect(p.imageOverride).toBeUndefined();
    expect(p.imagePullCredentialsTypeOverride).toBeUndefined();
    expect(p.computeTypeOverride).toBeUndefined();
    expect(p.timeoutInMinutesOverride).toBeUndefined();
    expect(p.privilegedModeOverride).toBeUndefined();
  });

  it("composes image_repo with the propeller version and uses SERVICE_ROLE for ECR", async () => {
    const { client, inputs } = mockCodeBuild();
    await startBuild(
      client,
      step(),
      config,
      ctx({
        codebuild: {
          image_repo: "111111111111.dkr.ecr.eu-central-2.amazonaws.com/deploy-runner-image",
        },
      }),
    );
    const p = inputs[0]!;
    expect(p.imageOverride).toBe(
      "111111111111.dkr.ecr.eu-central-2.amazonaws.com/deploy-runner-image:v2.3.0",
    );
    expect(p.imagePullCredentialsTypeOverride).toBe("SERVICE_ROLE");
  });

  it("prefers a full image over image_repo", async () => {
    const { client, inputs } = mockCodeBuild();
    await startBuild(
      client,
      step(),
      config,
      ctx({
        codebuild: {
          image: "111111111111.dkr.ecr.eu-central-2.amazonaws.com/deploy-runner-image:pinned",
          image_repo: "111111111111.dkr.ecr.eu-central-2.amazonaws.com/deploy-runner-image",
        },
      }),
    );
    expect(inputs[0]!.imageOverride).toBe(
      "111111111111.dkr.ecr.eu-central-2.amazonaws.com/deploy-runner-image:pinned",
    );
    expect(inputs[0]!.imagePullCredentialsTypeOverride).toBe("SERVICE_ROLE");
  });

  it("does not set SERVICE_ROLE for a non-ECR image", async () => {
    const { client, inputs } = mockCodeBuild();
    await startBuild(
      client,
      step(),
      config,
      ctx({ codebuild: { image: "docker.io/library/node:24" } }),
    );
    expect(inputs[0]!.imageOverride).toBe("docker.io/library/node:24");
    expect(inputs[0]!.imagePullCredentialsTypeOverride).toBeUndefined();
  });

  it("skips the image override when the step opts out via default_image", async () => {
    const { client, inputs } = mockCodeBuild();
    await startBuild(
      client,
      step({ codebuild: { default_image: true } }),
      config,
      ctx({
        codebuild: {
          image_repo: "111111111111.dkr.ecr.eu-central-2.amazonaws.com/deploy-runner-image",
        },
      }),
    );
    expect(inputs[0]!.imageOverride).toBeUndefined();
    expect(inputs[0]!.imagePullCredentialsTypeOverride).toBeUndefined();
  });

  it("applies the engine-resolved compute_type verbatim", async () => {
    const { client, inputs } = mockCodeBuild();
    // The engine already resolved precedence; the pipeline baseline is not
    // re-combined here, so the step value is used as-is.
    await startBuild(
      client,
      step({ codebuild: { compute_type: "BUILD_GENERAL1_LARGE" } }),
      config,
      ctx({ codebuild: { compute_type: "BUILD_GENERAL1_2XLARGE" } }),
    );
    expect(inputs[0]!.computeTypeOverride).toBe("BUILD_GENERAL1_LARGE");
  });

  it("applies the engine-resolved timeout verbatim", async () => {
    const { client, inputs } = mockCodeBuild();
    await startBuild(
      client,
      step({ codebuild: { timeout: 60 } }),
      config,
      ctx({ codebuild: { timeout: 999 } }),
    );
    expect(inputs[0]!.timeoutInMinutesOverride).toBe(60);
  });

  it("ignores the deprecated top-level timeout (the engine folds it)", async () => {
    const { client, inputs } = mockCodeBuild();
    await startBuild(client, step({ timeout: 45 }), config, ctx());
    expect(inputs[0]!.timeoutInMinutesOverride).toBeUndefined();
  });

  it("sets privileged mode only when the step declares it", async () => {
    const { client, inputs } = mockCodeBuild();
    await startBuild(client, step({ codebuild: { privileged: true } }), config, ctx());
    expect(inputs[0]!.privilegedModeOverride).toBe(true);
  });
});

describe("startBuild idempotency token", () => {
  it("sets a deterministic token for the same execution, project and phase", async () => {
    const { client, inputs } = mockCodeBuild();
    // Two calls with identical (executionId, project, deployAction) — as happens
    // when a durable step replays before its buildId is checkpointed. CodeBuild
    // dedupes on the token, so the duplicate collapses to one build.
    await startBuild(client, step({ project: "p1" }), config, ctx({ executionId: "e1" }));
    await startBuild(client, step({ project: "p1" }), config, ctx({ executionId: "e1" }));
    expect(inputs[0]!.idempotencyToken).toBeTruthy();
    expect(inputs[0]!.idempotencyToken).toBe(inputs[1]!.idempotencyToken);
  });

  it("stays within CodeBuild's 64-char token limit regardless of input length", async () => {
    const { client, inputs } = mockCodeBuild();
    // A realistic long execution name (pipeline__action__sha__timestamp) and a
    // pathologically long one. The token is a fixed-length hash digest, so its
    // length must not grow with the inputs and must never exceed 64.
    await startBuild(
      client,
      step({ project: "deploy-runner-workload" }),
      config,
      ctx({ executionId: "tenant-infra-dev__apply__95ee303__20260807T135558" }),
    );
    await startBuild(
      client,
      step({ project: "p".repeat(500) }),
      config,
      ctx({ executionId: "e".repeat(5000) }),
    );
    for (const p of inputs) {
      expect(p.idempotencyToken.length).toBeLessThanOrEqual(64);
    }
    // Fixed-length by construction: long and short inputs yield the same length.
    expect(inputs[0]!.idempotencyToken.length).toBe(inputs[1]!.idempotencyToken.length);
  });

  it("differs by phase, project and execution", async () => {
    const { client, inputs } = mockCodeBuild();
    await startBuild(
      client,
      step({ project: "p1" }),
      config,
      ctx({ executionId: "e1", deployAction: "apply" }),
    );
    await startBuild(
      client,
      step({ project: "p1" }),
      config,
      ctx({ executionId: "e1", deployAction: "plan" }),
    );
    await startBuild(
      client,
      step({ project: "p2" }),
      config,
      ctx({ executionId: "e1", deployAction: "apply" }),
    );
    await startBuild(
      client,
      step({ project: "p1" }),
      config,
      ctx({ executionId: "e2", deployAction: "apply" }),
    );
    const tokens = inputs.map((p) => p.idempotencyToken);
    // apply/plan (phase), p1/p2 (project), e1/e2 (execution) all yield distinct tokens
    expect(new Set(tokens).size).toBe(4);
  });
});
