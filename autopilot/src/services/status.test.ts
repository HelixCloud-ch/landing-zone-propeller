import { beforeEach, describe, expect, it, vi } from "vitest";

const sent: { Key?: string; Body?: string }[] = [];

vi.mock("@aws-sdk/client-s3", () => ({
  S3Client: class {
    async send(cmd: { input: { Key?: string; Body?: string } }) {
      sent.push(cmd.input);
    }
  },
  PutObjectCommand: class {
    constructor(public input: { Key?: string; Body?: string }) {}
  },
}));

const { StatusTracker } = await import("./status.js");

/** The state as the last write left it on S3. */
function written() {
  return JSON.parse(sent[sent.length - 1]!.Body!);
}

function tracker(projects: string[]) {
  return new StatusTracker(
    {
      executionId: "ns__apply__abc1234__20260730T120000",
      namespace: "ns",
      deployAction: "apply",
      bundleS3Uri: "s3://source-bucket/bundles/ns/abc1234.zip",
    } as never,
    projects,
  );
}

describe("StatusTracker", () => {
  beforeEach(() => (sent.length = 0));

  it("writes to executions/<id>/status.json", async () => {
    await tracker(["a"]).start();
    expect(sent[0]!.Key).toBe("executions/ns__apply__abc1234__20260730T120000/status.json");
  });

  it("starts with every step pending and one event", async () => {
    await tracker(["a", "b"]).start();
    const s = written();
    expect(s.steps.map((x: { status: string }) => x.status)).toEqual(["pending", "pending"]);
    expect(s.summary).toMatchObject({ pending: 2, running: 0, succeeded: 0 });
    expect(s.events).toEqual([{ at: expect.any(String), type: "execution_started" }]);
  });

  it("records events in the order they happened, not declaration order", async () => {
    const t = tracker(["first", "second"]);
    await t.start();
    await t.stepStarted("first");
    await t.stepStarted("second");
    // The second project finishes first: steps stays in pipeline order, events do not.
    await t.stepCompleted("second", "succeeded");
    await t.stepCompleted("first", "failed");
    await t.complete("failed");

    const s = written();
    expect(s.steps.map((x: { project: string }) => x.project)).toEqual(["first", "second"]);
    expect(s.events.map((e: { type: string; project?: string }) => [e.type, e.project])).toEqual([
      ["execution_started", undefined],
      ["step_started", "first"],
      ["step_started", "second"],
      ["step_succeeded", "second"],
      ["step_failed", "first"],
      ["execution_failed", undefined],
    ]);
  });

  it("carries the log key on the completion event", async () => {
    const t = tracker(["a"]);
    await t.start();
    await t.stepStarted("a");
    t.logWritten("a", "logs/exec/a.apply.log");
    await t.stepCompleted("a", "succeeded");

    const done = written().events.find((e: { type: string }) => e.type === "step_succeeded");
    expect(done.log).toBe("logs/exec/a.apply.log");
  });

  it("omits log when none was written, rather than emitting an empty one", async () => {
    const t = tracker(["a"]);
    await t.start();
    await t.stepCompleted("a", "failed");

    const done = written().events.find((e: { type: string }) => e.type === "step_failed");
    expect(done).not.toHaveProperty("log");
  });

  it("keeps a step it does not know about out of the state", async () => {
    const t = tracker(["a"]);
    await t.start();
    await t.stepStarted("ghost");
    expect(written().events).toHaveLength(1);
  });

  it("survives a failing S3 write, since status must not fail the pipeline", async () => {
    const t = tracker(["a"]);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (t as any).s3 = {
      send: () => Promise.reject(new Error("denied")),
    };
    await expect(t.start()).resolves.toBeUndefined();
  });
});
