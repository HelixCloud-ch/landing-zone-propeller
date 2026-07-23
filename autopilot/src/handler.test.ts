import type { DurableContext } from "@aws/durable-execution-sdk-js";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { execute } from "./handler.js";
import type { PipelineEvent } from "./types.js";

// --- SDK Mocks ---

vi.mock("@aws-sdk/client-codebuild", () => ({
  StartBuildCommand: vi.fn(function (this: any, input: any) {
    this._type = "StartBuild";
    this.input = input;
  }),
  BatchGetBuildsCommand: vi.fn(function (this: any, input: any) {
    this._type = "BatchGetBuilds";
    this.input = input;
  }),
  CodeBuildClient: vi.fn(function () {
    return {
      send: vi.fn(async (cmd: any) => {
        if (cmd._type === "StartBuild") {
          return { build: { id: "mock-build:12345" } };
        }
        return {
          builds: [
            {
              buildStatus: "SUCCEEDED",
              exportedEnvironmentVariables: [
                {
                  name: "PROPELLER_OUTPUTS_JSON",
                  value: JSON.stringify({ vpc_id: "vpc-mock", vpc_cidr: "10.0.0.0/16" }),
                },
              ],
              logs: { groupName: "/aws/codebuild/test", streamName: "abc123" },
            },
          ],
        };
      }),
    };
  }),
}));

vi.mock("@aws-sdk/client-s3", () => ({
  CopyObjectCommand: vi.fn(function (this: any, input: any) {
    this.input = input;
  }),
  PutObjectCommand: vi.fn(function (this: any, input: any) {
    this.input = input;
  }),
  S3Client: vi.fn(function () {
    return { send: vi.fn(async () => ({})) };
  }),
}));

vi.mock("@aws-sdk/client-cloudwatch-logs", () => ({
  GetLogEventsCommand: vi.fn(function (this: any, input: any) {
    this.input = input;
  }),
  CloudWatchLogsClient: vi.fn(function () {
    return {
      send: vi.fn(async () => ({
        events: [{ message: "Build completed" }],
        nextForwardToken: undefined,
      })),
    };
  }),
}));

vi.mock("@aws-sdk/client-lambda", () => ({
  LambdaClient: vi.fn(function () {
    return {
      send: vi.fn(async () => ({ DurableExecutions: [] })),
    };
  }),
  ListDurableExecutionsByFunctionCommand: vi.fn(function (this: any, input: any) {
    this.input = input;
  }),
}));

// --- Helpers ---

function createMockSSMClient(params: Record<string, string>) {
  return {
    send: vi.fn(async (command: any) => {
      const name = command.input?.Name as string;
      if (command.input?.Value !== undefined) {
        params[name] = command.input.Value;
        return {};
      }
      if (name in params) {
        return { Parameter: { Value: params[name] } };
      }
      const err = new Error(`Parameter not found: ${name}`);
      err.name = "ParameterNotFound";
      throw err;
    }),
  };
}

function createMockSTSClient() {
  return {
    send: vi.fn(async () => ({
      Credentials: {
        AccessKeyId: "AKIA_MOCK",
        SecretAccessKey: "mock-secret",
        SessionToken: "mock-token",
      },
    })),
  };
}

function createMockDurableContext(): DurableContext {
  const ctx: any = {
    executionId: "exec-mock-001",
    executionContext: {
      durableExecutionArn:
        "arn:aws:lambda:eu-central-2:123456789012:function:autopilot:qual/durable-execution/test-platform__deploy/exec-001",
    },
    step: vi.fn(async (_name: string, fn: () => any) => fn()),
    parallel: vi.fn(async (_name: string, branches: Array<any>) => {
      const results = await Promise.all(
        branches.map((b: any) => {
          const fn = typeof b === "function" ? b : b.func;
          return fn(ctx);
        }),
      );
      return { getResults: () => results };
    }),
    wait: vi.fn(async () => {}),
    waitForCallback: vi.fn(
      async (_name: string, submitter: (id: string, ctx: any) => Promise<void>) => {
        await submitter("mock-callback-id", {});
        return "approved";
      },
    ),
    runInChildContext: vi.fn(async (_name: string, fn: (child: DurableContext) => Promise<any>) =>
      fn(ctx),
    ),
  };
  return ctx as DurableContext;
}

function makeSimpleApplyEvent(): PipelineEvent {
  return {
    pipeline: {
      version: "1",
      namespace: "test-platform",
      propeller_version: "0.14.0",
      consumer_tags: { team: "platform-engineering" },
      stages: [
        {
          name: "network",
          steps: [
            {
              project: "project-a",
              source: "project-a",
              target: "account-alpha",
              inputs: [
                {
                  key: "/propeller/landing-zone/shared-parameters",
                  field: "transit_gw_id",
                  var: "tgw_id",
                },
              ],
              outputs: [
                { key: "/propeller/test-platform/project-a", ref: "vpc_id", field: "vpc_id" },
              ],
            },
            {
              project: "project-b",
              source: "project-b",
              target: "account-alpha",
              depends_on: ["project-a"],
              inputs: [
                { key: "/propeller/test-platform/project-a", field: "vpc_id", var: "vpc_id" },
              ],
              outputs: [
                {
                  key: "/propeller/test-platform/project-b",
                  ref: "route_table_ids",
                  field: "route_table_ids",
                },
              ],
            },
          ],
        },
      ],
    },
    bundle_s3_uri: "s3://test-bundle-bucket/test-platform/bundle.zip",
    deploy_action: "apply",
    git_sha: "a1b2c3d4e5f6",
  };
}

// --- Tests ---

describe("execute", () => {
  let ssmParams: Record<string, string>;

  beforeEach(() => {
    vi.clearAllMocks();
    ssmParams = {
      "/propeller/accounts/account-alpha/id": "111111111111",
      "/propeller/accounts/account-alpha/region": "eu-central-2",
      "/propeller/landing-zone/shared-parameters": JSON.stringify({
        outputs: { transit_gw_id: "tgw-0abc123" },
        meta: {},
      }),
      "/propeller/test-platform/project-a": JSON.stringify({
        outputs: { vpc_id: "vpc-0abc123" },
        meta: {},
      }),
    };
  });

  it("executes simple-apply pipeline successfully", async () => {
    const result = await execute(makeSimpleApplyEvent(), createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.status).toBe("succeeded");
    expect(result.summary).toEqual({ succeeded: 2, failed: 0, skipped: 0 });
  });

  it("respects DAG ordering — project-b runs after project-a", async () => {
    const ctx = createMockDurableContext();
    await execute(makeSimpleApplyEvent(), ctx, {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    const parallelCalls = (ctx.parallel as any).mock.calls;
    expect(parallelCalls[0][0]).toBe("wave:network:0");
    expect(parallelCalls[0][1]).toHaveLength(1);
    expect(parallelCalls[1][0]).toBe("wave:network:1");
    expect(parallelCalls[1][1]).toHaveLength(1);
  });

  it("writes pipeline state on success", async () => {
    await execute(makeSimpleApplyEvent(), createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(JSON.parse(ssmParams["/propeller/test-platform/state"]!)).toEqual({ state: "running" });
  });

  it("handles sleep mode with stage reversal", async () => {
    const event: PipelineEvent = {
      pipeline: {
        version: "1",
        namespace: "test-platform",
        propeller_version: "0.14.0",
        consumer_tags: {},
        stages: [
          {
            name: "infra",
            steps: [{ project: "vpc", target: "account-alpha", inputs: [], outputs: [] }],
          },
          {
            name: "compute",
            steps: [
              {
                project: "cluster",
                target: "account-alpha",
                sleep: true,
                sleep_config: { action: "destroy" },
                inputs: [],
                outputs: [],
              },
            ],
          },
        ],
      },
      bundle_s3_uri: "s3://test-bundle-bucket/test-platform/bundle.zip",
      deploy_action: "sleep",
      git_sha: "abc",
    };

    const result = await execute(event, createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.results.find((r) => r.project === "cluster")?.status).toBe("succeeded");
    expect(result.results.find((r) => r.project === "vpc")?.status).toBe("skipped");
  });

  it("filters to only specified projects", async () => {
    const event: PipelineEvent = { ...makeSimpleApplyEvent(), only: ["project-a"] };
    const result = await execute(event, createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.summary.succeeded).toBe(1);
    expect(result.results[0]?.project).toBe("project-a");
  });

  it("propagates failure across stages", async () => {
    const failingSSM = {
      send: vi.fn(async (command: any) => {
        if (command.input?.Value !== undefined) return {};
        if (command.input?.Name === "/propeller/accounts/account-alpha/id")
          throw new Error("Account not found");
        const err = new Error("Parameter not found");
        err.name = "ParameterNotFound";
        throw err;
      }),
    };

    const event: PipelineEvent = {
      pipeline: {
        version: "1",
        namespace: "test-platform",
        propeller_version: "0.14.0",
        consumer_tags: {},
        stages: [
          {
            name: "stage1",
            steps: [
              { project: "failing-project", target: "account-alpha", inputs: [], outputs: [] },
            ],
          },
          {
            name: "stage2",
            steps: [
              { project: "downstream-project", target: "account-alpha", inputs: [], outputs: [] },
            ],
          },
        ],
      },
      bundle_s3_uri: "s3://b/k.zip",
      deploy_action: "apply",
      git_sha: "sha",
    };

    const result = await execute(event, createMockDurableContext(), {
      ssm: failingSSM as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.status).toBe("failed");
    expect(result.results.find((r) => r.project === "failing-project")?.status).toBe("failed");
    expect(result.results.find((r) => r.project === "downstream-project")?.status).toBe("skipped");
  });

  it("returns error payload for invalid event", async () => {
    const result = await execute({ pipeline: { stages: [] } } as any, createMockDurableContext());
    expect(result.status).toBe("failed");
    expect(result.error).toContain("empty or missing");
  });

  it("supervised mode pauses for approval via waitForCallback", async () => {
    const ctx = createMockDurableContext();
    const event: PipelineEvent = {
      ...makeSimpleApplyEvent(),
      deploy_mode: "supervised",
    };

    const result = await execute(event, ctx, {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.status).toBe("succeeded");
    // waitForCallback should have been called for each project
    const callbackCalls = (ctx as any).waitForCallback.mock.calls;
    expect(callbackCalls.length).toBe(2);
    expect(callbackCalls[0][0]).toBe("approval");
    expect(callbackCalls[1][0]).toBe("approval");
  });

  it("assumes role in the correct target account", async () => {
    const mockSTS = createMockSTSClient();
    await execute(makeSimpleApplyEvent(), createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: mockSTS as any,
    });

    const stsCalls = mockSTS.send.mock.calls as any[][];
    // Every STS call should target account 111111111111 (the resolved account-alpha ID)
    for (const call of stsCalls) {
      expect(call[0].input.RoleArn).toContain("111111111111");
    }
    expect(stsCalls.length).toBeGreaterThan(0);
  });

  it("destroy without only or destroy_all returns validation error", async () => {
    const event: PipelineEvent = {
      ...makeSimpleApplyEvent(),
      deploy_action: "destroy",
    };
    const result = await execute(event, createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });
    expect(result.status).toBe("failed");
    expect(result.errorCode).toBe("VALIDATION_ERROR");
    expect(result.error).toContain("destroy requires");
  });

  it("destroy with only specified is allowed", async () => {
    const event: PipelineEvent = {
      ...makeSimpleApplyEvent(),
      deploy_action: "destroy",
      only: ["project-a"],
    };
    const result = await execute(event, createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });
    expect(result.status).toBe("succeeded");
  });

  it("destroy with destroy_all is allowed", async () => {
    const event: PipelineEvent = {
      ...makeSimpleApplyEvent(),
      deploy_action: "destroy",
      destroy_all: true,
    };
    const result = await execute(event, createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });
    expect(result.status).toBe("succeeded");
  });

  it("barrier: false merges stages into a single execution group", async () => {
    const ctx = createMockDurableContext();
    const event: PipelineEvent = {
      pipeline: {
        version: "1",
        namespace: "test-platform",
        propeller_version: "0.14.0",
        consumer_tags: {},
        stages: [
          {
            name: "infra",
            barrier: false,
            steps: [{ project: "vpc", target: "account-alpha", inputs: [], outputs: [] }],
          },
          {
            name: "data",
            barrier: false,
            steps: [{ project: "rds", target: "account-alpha", inputs: [], outputs: [] }],
          },
        ],
      },
      bundle_s3_uri: "s3://b/k.zip",
      deploy_action: "apply",
      git_sha: "sha",
    };

    const result = await execute(event, ctx, {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.status).toBe("succeeded");
    expect(result.summary.succeeded).toBe(2);
    // Both projects run in the same parallel wave (merged group)
    const parallelCalls = (ctx.parallel as any).mock.calls;
    expect(parallelCalls[0][0]).toBe("wave:infra+data:0");
    expect(parallelCalls[0][1]).toHaveLength(2);
  });

  it("barrier: true (default) keeps stages sequential", async () => {
    const ctx = createMockDurableContext();
    const event: PipelineEvent = {
      pipeline: {
        version: "1",
        namespace: "test-platform",
        propeller_version: "0.14.0",
        consumer_tags: {},
        stages: [
          {
            name: "infra",
            steps: [{ project: "vpc", target: "account-alpha", inputs: [], outputs: [] }],
          },
          {
            name: "data",
            steps: [{ project: "rds", target: "account-alpha", inputs: [], outputs: [] }],
          },
        ],
      },
      bundle_s3_uri: "s3://b/k.zip",
      deploy_action: "apply",
      git_sha: "sha",
    };

    await execute(event, ctx, {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    const parallelCalls = (ctx.parallel as any).mock.calls;
    expect(parallelCalls[0][0]).toBe("wave:infra:0");
    expect(parallelCalls[1][0]).toBe("wave:data:0");
  });

  it("blocks apply on sleeping pipeline", async () => {
    ssmParams["/propeller/test-platform/state"] = JSON.stringify({ state: "sleeping", sleep_preset: "deep" });

    const result = await execute(makeSimpleApplyEvent(), createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.status).toBe("failed");
    expect(result.errorCode).toBe("SLEEPING_PIPELINE");
  });

  it("force: true bypasses sleeping pipeline guard", async () => {
    ssmParams["/propeller/test-platform/state"] = JSON.stringify({ state: "sleeping", sleep_preset: "deep" });

    const event: PipelineEvent = { ...makeSimpleApplyEvent(), force: true };
    const result = await execute(event, createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.status).toBe("succeeded");
  });

  it("sleep without sleep_preset returns validation error when presets defined", async () => {
    const event: PipelineEvent = {
      pipeline: {
        ...makeSimpleApplyEvent().pipeline,
        sleep_presets: { light: { "project-a": "stop" } },
      },
      bundle_s3_uri: "s3://b/k.zip",
      deploy_action: "sleep",
      git_sha: "sha",
    };

    const result = await execute(event, createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.status).toBe("failed");
    expect(result.error).toContain("sleep requires a sleep_preset");
  });

  it("mixed barrier/non-barrier stages: non-barrier stages merge, barriers stay separate", async () => {
    const ctx = createMockDurableContext();
    const event: PipelineEvent = {
      pipeline: {
        version: "1",
        namespace: "test-platform",
        propeller_version: "0.14.0",
        consumer_tags: {},
        stages: [
          {
            name: "discover",
            steps: [{ project: "vpc", target: "account-alpha", inputs: [], outputs: [] }],
          },
          {
            name: "cluster",
            barrier: false,
            steps: [{ project: "eks", target: "account-alpha", inputs: [], outputs: [] }],
          },
          {
            name: "databases",
            barrier: false,
            steps: [{ project: "rds", target: "account-alpha", inputs: [], outputs: [] }],
          },
          {
            name: "apps",
            steps: [{ project: "app", target: "account-alpha", inputs: [], outputs: [] }],
          },
        ],
      },
      bundle_s3_uri: "s3://b/k.zip",
      deploy_action: "apply",
      git_sha: "sha",
    };

    await execute(event, ctx, {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    const parallelCalls = (ctx.parallel as any).mock.calls;
    // Group 1: discover (barrier)
    expect(parallelCalls[0][0]).toBe("wave:discover:0");
    expect(parallelCalls[0][1]).toHaveLength(1);
    // Group 2: cluster+databases (merged non-barrier)
    expect(parallelCalls[1][0]).toBe("wave:cluster+databases:0");
    expect(parallelCalls[1][1]).toHaveLength(2);
    // Group 3: apps (barrier)
    expect(parallelCalls[2][0]).toBe("wave:apps:0");
    expect(parallelCalls[2][1]).toHaveLength(1);
  });

  it("wake without preset uses stored sleep_modes from SSM state", async () => {
    // Simulate a previously slept pipeline with stored modes
    ssmParams["/propeller/test-platform/state"] = JSON.stringify({
      state: "sleeping",
      sleep_preset: "deep",
      sleep_modes: { "rds": "snapshot" },
    });

    const event: PipelineEvent = {
      pipeline: {
        version: "1",
        namespace: "test-platform",
        propeller_version: "0.14.0",
        consumer_tags: {},
        stages: [
          {
            name: "data",
            steps: [
              { project: "rds", target: "account-alpha", sleep: true, sleep_config: { action: "destroy" }, inputs: [], outputs: [] },
              { project: "vpc", target: "account-alpha", inputs: [], outputs: [] },
            ],
          },
        ],
        // Preset definition has been CHANGED (rds removed) — but stored modes should take priority
        sleep_presets: { deep: { vpc: "destroy" } },
      },
      bundle_s3_uri: "s3://b/k.zip",
      deploy_action: "wake",
      git_sha: "sha",
      // No sleep_preset specified — should fall back to stored state
    };

    const result = await execute(event, createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.status).toBe("succeeded");
    // rds wakes (from stored modes), vpc is skipped (not in stored modes)
    expect(result.results.find((r) => r.project === "rds")?.status).toBe("succeeded");
    expect(result.results.find((r) => r.project === "vpc")?.status).toBe("skipped");
  });

  it("sleep with valid preset resolves modes and executes", async () => {
    const event: PipelineEvent = {
      pipeline: {
        version: "1",
        namespace: "test-platform",
        propeller_version: "0.14.0",
        consumer_tags: {},
        stages: [
          {
            name: "data",
            steps: [
              { project: "rds", target: "account-alpha", sleep: true, sleep_config: { action: "destroy" }, inputs: [], outputs: [] },
              { project: "vpc", target: "account-alpha", inputs: [], outputs: [] },
            ],
          },
        ],
        sleep_presets: { deep: { rds: "destroy" } },
      },
      bundle_s3_uri: "s3://b/k.zip",
      deploy_action: "sleep",
      sleep_preset: "deep",
      git_sha: "sha",
    };

    const result = await execute(event, createMockDurableContext(), {
      ssm: createMockSSMClient(ssmParams) as any,
      sts: createMockSTSClient() as any,
    });

    expect(result.status).toBe("succeeded");
    // rds participates (in preset), vpc is skipped (not in preset)
    expect(result.results.find((r) => r.project === "rds")?.status).toBe("succeeded");
    expect(result.results.find((r) => r.project === "vpc")?.status).toBe("skipped");
  });
});
