import { describe, expect, it } from "vitest";
import { applyTransform, applyTransforms } from "./transform.js";

describe("applyTransform", () => {
  it("wraps string in list", async () => {
    const result = await applyTransform("10.0.0.0/8", "[$]");
    expect(JSON.parse(result)).toEqual(["10.0.0.0/8"]);
  });

  it("map lookup", async () => {
    const result = await applyTransform(
      "small",
      '$lookup({"small":"db.t3.medium","medium":"db.m5.large"}, $)',
    );
    expect(JSON.parse(result)).toBe("db.t3.medium");
  });

  it("extract key from JSON object", async () => {
    const result = await applyTransform(
      '{"private":["s-1","s-2"],"data":["s-3"]}',
      "private",
    );
    expect(JSON.parse(result)).toEqual(["s-1", "s-2"]);
  });

  it("conditional: non-empty wraps in list", async () => {
    const result = await applyTransform("10.0.0.0/8", '$ = "" ? [] : [$]');
    expect(JSON.parse(result)).toEqual(["10.0.0.0/8"]);
  });

  it("conditional: empty produces empty list", async () => {
    const result = await applyTransform("", '$ = "" ? [] : [$]');
    expect(JSON.parse(result)).toEqual([]);
  });

  it("split string into list", async () => {
    const result = await applyTransform("sg-123,sg-456", '$split($, ",")');
    expect(JSON.parse(result)).toEqual(["sg-123", "sg-456"]);
  });

  it("cast to number", async () => {
    const result = await applyTransform("42", "$number($)");
    expect(JSON.parse(result)).toBe(42);
  });

  it("cast to boolean", async () => {
    const result = await applyTransform("true", '$ = "true"');
    expect(JSON.parse(result)).toBe(true);
  });

  it("cast to boolean (false)", async () => {
    const result = await applyTransform("false", '$ = "true"');
    expect(JSON.parse(result)).toBe(false);
  });

  it("string concatenation", async () => {
    const result = await applyTransform("my-db", '"propeller-" & $');
    expect(JSON.parse(result)).toBe("propeller-my-db");
  });

  it("nested extract with fallback", async () => {
    const result = await applyTransform(
      '{"private":["s-1"],"data":["s-3","s-4"]}',
      "data ? data : []",
    );
    expect(JSON.parse(result)).toEqual(["s-3", "s-4"]);
  });

  it("nested extract missing key uses fallback", async () => {
    const result = await applyTransform('{"private":["s-1"]}', "data ? data : []");
    expect(JSON.parse(result)).toEqual([]);
  });

  it("map with default fallback", async () => {
    const expr = '$lookup({"small":"db.t3.medium"}, $) ? $lookup({"small":"db.t3.medium"}, $) : "default"';
    const result = await applyTransform("unknown", expr);
    expect(JSON.parse(result)).toBe("default");
  });

  it("identity", async () => {
    const result = await applyTransform("hello", "$");
    expect(JSON.parse(result)).toBe("hello");
  });

  it("string prefix", async () => {
    const result = await applyTransform(
      "/propeller-smoke/autopilot-v2/app-alpha",
      '"jq-ok: " & $',
    );
    expect(JSON.parse(result)).toBe("jq-ok: /propeller-smoke/autopilot-v2/app-alpha");
  });
});

describe("applyTransforms", () => {
  it("transforms only inputs with expressions", async () => {
    const inputs = {
      vpc_id: "vpc-123",
      allowed_cidrs: "10.0.0.0/8",
      instance_class: "small",
    };
    const transforms = {
      allowed_cidrs: "[$]",
      instance_class: '$lookup({"small":"db.t3.medium"}, $)',
    };

    const result = await applyTransforms(inputs, transforms);

    expect(result.vpc_id).toBe("vpc-123"); // untransformed
    expect(JSON.parse(result.allowed_cidrs!)).toEqual(["10.0.0.0/8"]);
    expect(JSON.parse(result.instance_class!)).toBe("db.t3.medium");
  });

  it("returns empty object for empty inputs", async () => {
    const result = await applyTransforms({}, {});
    expect(result).toEqual({});
  });
});
