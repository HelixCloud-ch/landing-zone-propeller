/**
 * Pipeline-wide policies.
 *
 * Currently one kind: soft_fail. A step whose name matches a policy's glob,
 * whose current deploy action is in the policy's `actions` list, and whose
 * invocation shape (--only vs full) matches the policy's `on_only`, is
 * treated as non-blocking on failure.
 */

import type { DeployAction, PipelinePolicies } from "../types.js";

/** Compile a step-name glob (`*`, `?`) into an anchored full-match regex. */
function globToRegex(glob: string): RegExp {
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  const pattern = escaped.replace(/\*/g, ".*").replace(/\?/g, ".");
  return new RegExp(`^${pattern}$`);
}

/**
 * True when a failing step should be treated as soft-fail per pipeline
 * policies. Callers should skip cascade and hard-fail counting when true.
 */
export function isSoftFail(
  project: string,
  action: DeployAction,
  policies: PipelinePolicies | undefined,
  hasOnlyFilter: boolean,
): boolean {
  const rules = policies?.soft_fail;
  if (!rules || rules.length === 0) return false;
  for (const rule of rules) {
    if (!rule.actions.includes(action)) continue;
    if (hasOnlyFilter && !rule.on_only) continue;
    if (globToRegex(rule.match).test(project)) return true;
  }
  return false;
}
