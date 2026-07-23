import type { SSMClient } from "@aws-sdk/client-ssm";
import { describe, expect, it, vi } from "vitest";
import type { PipelineContext, StepConfig } from "../types.js";
import {
  getParameter,
  getParameterOptional,
  prepareBuildConfig,
  readProjectBlob,
  resolveInputs,
  writeOutputs,
  writePipelineState,
} from "./ssm.js";

function createMockSSMClient(params: Record<string, string>) {
  const sendFn = vi.fn(async (command: any) => {
    const name = command.input?.Name as string;

    if (
      command.constructor.name === "GetParameterCommand" ||
      (command.input?.Name !== undefined && !command.input?.Value)
    ) {
      if (name in params) {
        return { Parameter: { Value: params[name] } };
      }
      const err = new Error(`Parameter not found: ${name}`);
      err.name = "ParameterNotFound";
      throw err;
    }

    if (command.input?.Value !== undefined) {
      // PutParameterCommand
      params[name] = command.input.Value;
      return {};
    }

    throw new Error(`Unexpected command`);
  });

  return { send: sendFn } as unknown as SSMClient & { send: ReturnType<typeof vi.fn> };
}

describe("getParameter", () => {
  it("returns parameter value", async () => {
    const client = createMockSSMClient({ "/test/param": "hello" });
    const result = await getParameter(client, "/test/param");
    expect(result).toBe("hello");
  });

  it("throws on missing parameter", async () => {
    const client = createMockSSMClient({});
    await expect(getParameter(client, "/missing")).rejects.toThrow("Parameter not found");
  });
});

describe("getParameterOptional", () => {
  it("returns value when parameter exists", async () => {
    const client = createMockSSMClient({ "/test/param": "world" });
    const result = await getParameterOptional(client, "/test/param");
    expect(result).toBe("world");
  });

  it("returns null for ParameterNotFound", async () => {
    const client = createMockSSMClient({});
    const result = await getParameterOptional(client, "/missing");
    expect(result).toBeNull();
  });
});

describe("resolveInputs", () => {
  it("resolves field-based input from blob", async () => {
    const blob = JSON.stringify({
      outputs: { vpc_id: "vpc-abc123", subnet_ids: "subnet-1" },
      meta: {},
    });
    const client = createMockSSMClient({
      "/propeller/test-ns/project-a": blob,
    });

    const step: StepConfig = {
      project: "project-b",
      inputs: [
        { key: "/propeller/test-ns/project-a", field: "vpc_id", var: "vpc_id" },
        { key: "/propeller/test-ns/project-a", field: "subnet_ids", var: "subnets" },
      ],
      outputs: [],
    };

    const result = await resolveInputs(client, step, "test-ns");
    expect(result).toEqual({ vpc_id: "vpc-abc123", subnets: "subnet-1" });
    // Should cache blob reads - only one GetParameter call for the blob
    expect(client.send).toHaveBeenCalledTimes(1);
  });

  it("resolves raw parameter input", async () => {
    const client = createMockSSMClient({
      "/some/direct/param": "direct-value",
    });

    const step: StepConfig = {
      project: "project-x",
      inputs: [{ key: "/some/direct/param", var: "my_var" }],
      outputs: [],
    };

    const result = await resolveInputs(client, step, "test-ns");
    expect(result).toEqual({ my_var: "direct-value" });
  });

  it("handles EMPTY_SENTINEL as empty string", async () => {
    const client = createMockSSMClient({
      "/some/param": "__EMPTY__",
    });

    const step: StepConfig = {
      project: "project-x",
      inputs: [{ key: "/some/param", var: "empty_var" }],
      outputs: [],
    };

    const result = await resolveInputs(client, step, "test-ns");
    expect(result).toEqual({ empty_var: "" });
  });

  it("handles missing optional parameter as empty string", async () => {
    const client = createMockSSMClient({});

    const step: StepConfig = {
      project: "project-x",
      inputs: [{ key: "/missing/param", var: "missing_var" }],
      outputs: [],
    };

    const result = await resolveInputs(client, step, "test-ns");
    expect(result).toEqual({ missing_var: "" });
  });
});

describe("prepareBuildConfig", () => {
  it("resolves account and region from SSM", async () => {
    const blob = JSON.stringify({
      outputs: { transit_gw_id: "tgw-123" },
      meta: {},
    });
    const client = createMockSSMClient({
      "/propeller/accounts/account-alpha/id": "111111111111",
      "/propeller/accounts/account-alpha/region": "eu-central-1",
      "/propeller/test-ns/shared-params": blob,
    });

    const step: StepConfig = {
      project: "my-project",
      target: "account-alpha",
      inputs: [{ key: "/propeller/test-ns/shared-params", field: "transit_gw_id", var: "tgw_id" }],
      outputs: [],
    };

    const config = await prepareBuildConfig(client, step, "test-ns");
    expect(config.accountId).toBe("111111111111");
    expect(config.region).toBe("eu-central-1");
    expect(config.codebuildProject).toBe("deploy-runner");
    expect(config.inputs).toEqual({ tgw_id: "tgw-123" });
  });

  it("uses custom runner name", async () => {
    const client = createMockSSMClient({
      "/propeller/accounts/default/id": "222222222222",
      "/propeller/accounts/default/region": "us-west-2",
    });

    const step: StepConfig = {
      project: "custom-runner-project",
      runner: "custom-runner",
      inputs: [],
      outputs: [],
    };

    const config = await prepareBuildConfig(client, step, "ns");
    expect(config.codebuildProject).toBe("custom-runner");
    expect(config.runner).toBe("custom-runner");
  });
});

describe("writeOutputs", () => {
  it("writes individual params and project blob", async () => {
    const params: Record<string, string> = {};
    const client = createMockSSMClient(params);

    const step: StepConfig = {
      project: "my-project",
      inputs: [],
      outputs: [
        { key: "/propeller/test-ns/my-project/vpc_id", ref: "vpc_id" },
        { key: "/propeller/test-ns/my-project", ref: "cidr", field: "cidr" },
      ],
    };

    const exportedVars = [
      {
        name: "PROPELLER_OUTPUTS_JSON",
        value: JSON.stringify({ vpc_id: "vpc-new", cidr: "10.0.0.0/16" }),
      },
    ];

    const pctx: PipelineContext = {
      bundleS3Uri: "s3://bucket/key.zip",
      deployAction: "apply",
      namespace: "test-ns",
      propellerVersion: "0.14.0",
      gitSha: "abc123",
      consumerTags: {},
      executionId: "exec-test-123",
      supervised: false,
      sleepModes: {},
    };

    const written = await writeOutputs(client, step, exportedVars, "build:123", pctx);

    expect(written.vpc_id).toBe("/propeller/test-ns/my-project/vpc_id");
    expect(written.cidr).toBe("/propeller/test-ns/my-project[cidr]");
    expect(params["/propeller/test-ns/my-project/vpc_id"]).toBe("vpc-new");

    const blob = JSON.parse(params["/propeller/test-ns/my-project"]!);
    expect(blob.outputs.cidr).toBe("10.0.0.0/16");
    expect(blob.meta.propeller_version).toBe("0.14.0");
    expect(blob.meta.git_sha).toBe("abc123");
  });

  it("writes EMPTY_SENTINEL for empty string values", async () => {
    const params: Record<string, string> = {};
    const client = createMockSSMClient(params);

    const step: StepConfig = {
      project: "proj",
      inputs: [],
      outputs: [{ key: "/propeller/ns/proj/empty", ref: "empty_val" }],
    };

    const exportedVars = [
      { name: "PROPELLER_OUTPUTS_JSON", value: JSON.stringify({ empty_val: "" }) },
    ];

    const pctx: PipelineContext = {
      bundleS3Uri: "s3://b/k",
      deployAction: "apply",
      namespace: "ns",
      propellerVersion: "1.0.0",
      gitSha: "sha",
      consumerTags: {},
      executionId: "exec-test-123",
      supervised: false,
      sleepModes: {},
    };

    await writeOutputs(client, step, exportedVars, "build:1", pctx);
    expect(params["/propeller/ns/proj/empty"]).toBe("__EMPTY__");
  });
});

describe("readProjectBlob", () => {
  it("returns parsed blob when it exists", async () => {
    const blob = JSON.stringify({
      outputs: { vpc_id: "vpc-123" },
      meta: { propeller_version: "1.0", deployed_at: "2025-01-01", build_id: "b1", git_sha: "abc" },
    });
    const client = createMockSSMClient({ "/propeller/ns/proj": blob });

    const result = await readProjectBlob(client, "ns", "proj");
    expect(result).not.toBeNull();
    expect(result!.outputs.vpc_id).toBe("vpc-123");
  });

  it("returns null when blob does not exist", async () => {
    const client = createMockSSMClient({});
    const result = await readProjectBlob(client, "ns", "missing");
    expect(result).toBeNull();
  });
});

describe("writePipelineState", () => {
  it("writes state to correct SSM path", async () => {
    const params: Record<string, string> = {};
    const client = createMockSSMClient(params);

    await writePipelineState(client, "test-ns", "running");
    expect(JSON.parse(params["/propeller/test-ns/state"]!)).toEqual({ state: "running" });
  });

  it("stores sleep_preset when sleeping", async () => {
    const params: Record<string, string> = {};
    const client = createMockSSMClient(params);

    await writePipelineState(client, "test-ns", "sleeping", "deep");
    expect(JSON.parse(params["/propeller/test-ns/state"]!)).toEqual({
      state: "sleeping",
      sleep_preset: "deep",
    });
  });

  it("stores sleep_modes per project when sleeping", async () => {
    const params: Record<string, string> = {};
    const client = createMockSSMClient(params);

    const modes = { "rds-oracle-1": "snapshot", "eks-cluster-1": "destroy" };
    await writePipelineState(client, "test-ns", "sleeping", "deep", modes);
    expect(JSON.parse(params["/propeller/test-ns/state"]!)).toEqual({
      state: "sleeping",
      sleep_preset: "deep",
      sleep_modes: { "rds-oracle-1": "snapshot", "eks-cluster-1": "destroy" },
    });
  });
});
