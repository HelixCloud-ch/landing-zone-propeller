/**
 * Pure DAG logic for the Propeller Autopilot pipeline executor.
 *
 * Handles dependency graph construction, readiness checks, and
 * failure propagation (transitive dependent discovery).
 */

import type { DependencyGraph, StepConfig } from "../types.js";

/**
 * Build a dependency graph for a set of steps.
 *
 * Dependencies come from two sources:
 * 1. Explicit `depends_on` fields
 * 2. Implicit from `inputs` — if a step reads from "project-a.field",
 *    it depends on project-a (only if project-a is in the same step set)
 *
 * @param steps - Steps to build the DAG for.
 * @returns A Map from project name to its set of dependencies.
 */
export function buildDag(steps: StepConfig[]): DependencyGraph {
  const knownProjects = new Set(steps.map((s) => s.project));
  const dag: DependencyGraph = new Map();

  for (const step of steps) {
    const deps = new Set<string>();

    // Explicit depends_on
    for (const d of step.depends_on ?? []) {
      if (knownProjects.has(d)) deps.add(d);
    }

    // Implicit from inputs: extract source project from SSM key path
    // Resolved inputs have key like "/propeller/{namespace}/{project}" or
    // raw field-based reads from another project's blob.
    for (const inp of step.inputs ?? []) {
      // The key format is /propeller/{namespace}/{project} for blob reads
      const keyParts = (inp.key ?? "").split("/").filter(Boolean);
      // Pattern: ["propeller", namespace, project] → project is index 2
      if (keyParts.length >= 3 && keyParts[0] === "propeller") {
        const srcProject = keyParts[2]!;
        if (knownProjects.has(srcProject) && srcProject !== step.project) {
          deps.add(srcProject);
        }
      }
    }

    dag.set(step.project, deps);
  }

  return dag;
}

/**
 * Reverse a dependency graph (invert all edges).
 *
 * Used for destructive actions (destroy, sleep): if B depends on A during
 * apply, then during destroy B must be torn down before A.
 *
 * @param dag - The original dependency graph.
 * @returns A new graph with reversed edges.
 */
export function reverseDag(dag: DependencyGraph): DependencyGraph {
  const reversed: DependencyGraph = new Map();

  for (const project of dag.keys()) {
    reversed.set(project, new Set());
  }

  for (const [project, deps] of dag) {
    for (const dep of deps) {
      const depSet = reversed.get(dep);
      if (depSet) depSet.add(project);
    }
  }

  return reversed;
}

/**
 * Find projects that are ready to execute (all dependencies satisfied).
 *
 * A project is ready when:
 * - It hasn't been completed, failed, or skipped yet
 * - All its dependencies are in the completed set (not failed/skipped)
 *
 * @param dag - The dependency graph.
 * @param completed - Projects that completed successfully.
 * @param failed - Projects that failed.
 * @param skipped - Projects that were skipped.
 * @returns Sorted list of project names ready for execution.
 */
export function findReady(
  dag: DependencyGraph,
  completed: Set<string>,
  failed: Set<string>,
  skipped: Set<string>,
): string[] {
  const done = new Set([...completed, ...failed, ...skipped]);
  const ready: string[] = [];

  for (const [project, deps] of dag) {
    if (done.has(project)) continue;
    const allDepsMet = [...deps].every((d) => completed.has(d));
    if (allDepsMet) ready.push(project);
  }

  return ready.sort();
}

/**
 * Find all transitive dependents of a project in the DAG.
 *
 * Used for failure propagation — when a project fails, all its
 * direct and indirect dependents are skipped.
 *
 * @param dag - The dependency graph.
 * @param project - The failed project name.
 * @returns Set of all project names that transitively depend on the given project.
 */
export function findDependents(dag: DependencyGraph, project: string): Set<string> {
  const result = new Set<string>();
  const frontier = [project];

  while (frontier.length > 0) {
    const current = frontier.pop()!;
    for (const [p, deps] of dag) {
      if (deps.has(current) && !result.has(p)) {
        result.add(p);
        frontier.push(p);
      }
    }
  }

  return result;
}
