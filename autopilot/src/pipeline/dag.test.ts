import { describe, expect, it } from "vitest";
import type { StepConfig } from "../types.js";
import { buildDag, findDependents, findReady } from "./dag.js";

const twoProjectsWithDep: StepConfig[] = [
  { project: "project-a", inputs: [], outputs: [] },
  { project: "project-b", depends_on: ["project-a"], inputs: [], outputs: [] },
];

const threeProjectsFanOut: StepConfig[] = [
  { project: "project-a", inputs: [], outputs: [] },
  { project: "project-b", depends_on: ["project-a"], inputs: [], outputs: [] },
  { project: "project-c", depends_on: ["project-a"], inputs: [], outputs: [] },
];

describe("buildDag", () => {
  it("builds graph with dependency", () => {
    const dag = buildDag(twoProjectsWithDep);
    expect(dag.size).toBe(2);
    expect(dag.get("project-a")).toEqual(new Set());
    expect(dag.get("project-b")).toEqual(new Set(["project-a"]));
  });

  it("filters out cross-stage dependencies", () => {
    const steps: StepConfig[] = [
      { project: "x", depends_on: ["external"], inputs: [], outputs: [] },
      { project: "y", depends_on: ["x"], inputs: [], outputs: [] },
    ];
    const dag = buildDag(steps);
    expect(dag.get("x")).toEqual(new Set());
    expect(dag.get("y")).toEqual(new Set(["x"]));
  });

  it("handles steps with no dependencies", () => {
    const steps: StepConfig[] = [
      { project: "a", inputs: [], outputs: [] },
      { project: "b", inputs: [], outputs: [] },
    ];
    const dag = buildDag(steps);
    expect(dag.get("a")).toEqual(new Set());
    expect(dag.get("b")).toEqual(new Set());
  });
});

describe("findReady", () => {
  it("returns root projects when nothing is done", () => {
    const dag = buildDag(twoProjectsWithDep);
    expect(findReady(dag, new Set(), new Set(), new Set())).toEqual(["project-a"]);
  });

  it("returns dependent after dependency completes", () => {
    const dag = buildDag(twoProjectsWithDep);
    expect(findReady(dag, new Set(["project-a"]), new Set(), new Set())).toEqual(["project-b"]);
  });

  it("blocks projects whose dependencies failed", () => {
    const dag = buildDag(twoProjectsWithDep);
    expect(findReady(dag, new Set(), new Set(["project-a"]), new Set())).toEqual([]);
  });

  it("returns independent projects in sorted order", () => {
    const steps: StepConfig[] = [
      { project: "c", inputs: [], outputs: [] },
      { project: "a", inputs: [], outputs: [] },
      { project: "b", inputs: [], outputs: [] },
    ];
    expect(findReady(buildDag(steps), new Set(), new Set(), new Set())).toEqual(["a", "b", "c"]);
  });
});

describe("findDependents", () => {
  it("finds direct dependents (fan-out)", () => {
    const dag = buildDag(threeProjectsFanOut);
    expect(findDependents(dag, "project-a")).toEqual(new Set(["project-b", "project-c"]));
  });

  it("finds transitive dependents (chain)", () => {
    const steps: StepConfig[] = [
      { project: "a", inputs: [], outputs: [] },
      { project: "b", depends_on: ["a"], inputs: [], outputs: [] },
      { project: "c", depends_on: ["b"], inputs: [], outputs: [] },
    ];
    expect(findDependents(buildDag(steps), "a")).toEqual(new Set(["b", "c"]));
  });

  it("returns empty set when no dependents", () => {
    const steps: StepConfig[] = [
      { project: "a", inputs: [], outputs: [] },
      { project: "b", inputs: [], outputs: [] },
    ];
    expect(findDependents(buildDag(steps), "a")).toEqual(new Set());
  });
});

import { reverseDag } from "./dag.js";

describe("reverseDag", () => {
  it("inverts edges (A→B becomes B→A)", () => {
    const dag = buildDag(twoProjectsWithDep);
    const reversed = reverseDag(dag);
    // Original: B depends on A. Reversed: A depends on B.
    expect(reversed.get("project-a")).toEqual(new Set(["project-b"]));
    expect(reversed.get("project-b")).toEqual(new Set());
  });

  it("inverts fan-out into fan-in", () => {
    const dag = buildDag(threeProjectsFanOut);
    const reversed = reverseDag(dag);
    // Original: B,C depend on A. Reversed: A depends on B and C.
    expect(reversed.get("project-a")).toEqual(new Set(["project-b", "project-c"]));
    expect(reversed.get("project-b")).toEqual(new Set());
    expect(reversed.get("project-c")).toEqual(new Set());
  });

  it("preserves independent projects (no edges)", () => {
    const steps: StepConfig[] = [
      { project: "a", inputs: [], outputs: [] },
      { project: "b", inputs: [], outputs: [] },
    ];
    const reversed = reverseDag(buildDag(steps));
    expect(reversed.get("a")).toEqual(new Set());
    expect(reversed.get("b")).toEqual(new Set());
  });

  it("reversed DAG executes dependents first in findReady", () => {
    const dag = buildDag(twoProjectsWithDep);
    const reversed = reverseDag(dag);
    // In reversed DAG, project-b has no deps so it's ready first (destroy order)
    expect(findReady(reversed, new Set(), new Set(), new Set())).toEqual(["project-b"]);
    // After B completes, A becomes ready
    expect(findReady(reversed, new Set(["project-b"]), new Set(), new Set())).toEqual([
      "project-a",
    ]);
  });
});
