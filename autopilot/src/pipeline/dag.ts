/**
 * Pure DAG logic for the Propeller Autopilot pipeline executor.
 *
 * Handles dependency graph construction, readiness checks, and
 * failure propagation (transitive dependent discovery).
 */

import type { DependencyGraph, StepConfig } from "../types.js";

/**
 * Build a dependency graph for steps within a stage.
 *
 * Only includes dependencies that exist within the same stage
 * (cross-stage deps are handled by stage ordering).
 *
 * @param steps - All steps in the current stage.
 * @returns A Map from project name to its set of in-stage dependencies.
 */
export function buildDag(steps: StepConfig[]): DependencyGraph {
  const stageProjects = new Set(steps.map((s) => s.project));
  const dag: DependencyGraph = new Map();

  for (const step of steps) {
    const deps = new Set((step.depends_on ?? []).filter((d) => stageProjects.has(d)));
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
