import { describe, expect, it } from "vitest";
import type { PipelinePolicies } from "../types.js";
import { isSoftFail } from "./policies.js";

describe("isSoftFail", () => {
  it("returns false when no policies are configured", () => {
    expect(isSoftFail("bundle-x", "wake", undefined, false)).toBe(false);
    expect(isSoftFail("bundle-x", "wake", {}, false)).toBe(false);
    expect(isSoftFail("bundle-x", "wake", { soft_fail: [] }, false)).toBe(false);
  });

  it("matches glob and action", () => {
    const policies: PipelinePolicies = {
      soft_fail: [{ match: "bundle-*", actions: ["wake"] }],
    };
    expect(isSoftFail("bundle-app-a", "wake", policies, false)).toBe(true);
    expect(isSoftFail("bundle-app-a", "apply", policies, false)).toBe(false);
    expect(isSoftFail("eks-cluster", "wake", policies, false)).toBe(false);
  });

  it("supports ? single-char glob", () => {
    const policies: PipelinePolicies = {
      soft_fail: [{ match: "app-?", actions: ["wake"] }],
    };
    expect(isSoftFail("app-a", "wake", policies, false)).toBe(true);
    expect(isSoftFail("app-ab", "wake", policies, false)).toBe(false);
  });

  it("anchors match (full name, not substring)", () => {
    const policies: PipelinePolicies = {
      soft_fail: [{ match: "bundle-*", actions: ["wake"] }],
    };
    expect(isSoftFail("pre-bundle-x", "wake", policies, false)).toBe(false);
    expect(isSoftFail("bundle-x-post", "wake", policies, false)).toBe(true);
  });

  it("on_only=false: policy ignored when --only filter is set (default)", () => {
    const policies: PipelinePolicies = {
      soft_fail: [{ match: "bundle-*", actions: ["wake"] }],
    };
    expect(isSoftFail("bundle-x", "wake", policies, true)).toBe(false);
  });

  it("on_only=true: policy applies even with --only filter", () => {
    const policies: PipelinePolicies = {
      soft_fail: [{ match: "bundle-*", actions: ["wake"], on_only: true }],
    };
    expect(isSoftFail("bundle-x", "wake", policies, true)).toBe(true);
  });

  it("any policy match wins", () => {
    const policies: PipelinePolicies = {
      soft_fail: [
        { match: "eks-*", actions: ["apply"] },
        { match: "bundle-*", actions: ["wake"] },
        { match: "monitoring-*", actions: ["wake", "apply"] },
      ],
    };
    expect(isSoftFail("bundle-x", "wake", policies, false)).toBe(true);
    expect(isSoftFail("monitoring-y", "apply", policies, false)).toBe(true);
    expect(isSoftFail("bundle-x", "apply", policies, false)).toBe(false);
  });

  it("escapes regex metacharacters in glob", () => {
    const policies: PipelinePolicies = {
      soft_fail: [{ match: "app.legacy", actions: ["wake"] }],
    };
    expect(isSoftFail("app.legacy", "wake", policies, false)).toBe(true);
    expect(isSoftFail("appXlegacy", "wake", policies, false)).toBe(false);
  });
});
