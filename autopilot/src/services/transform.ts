/**
 * Input transforms using JSONata expressions.
 *
 * Transforms are applied in the Lambda after reading input values from SSM,
 * before passing them to CodeBuild. The transformed value replaces the raw
 * string in the PROPELLER_INPUT_* env var.
 */

import jsonata from "jsonata";

/**
 * Apply a JSONata expression to transform an input value.
 *
 * The raw value (string from SSM) is available as `$` in the expression.
 * For values that are valid JSON, they're parsed first so the expression
 * can access nested fields directly.
 *
 * @returns The transformed value as a JSON-encoded string suitable for
 *          inclusion in _propeller.auto.tfvars.json
 */
export async function applyTransform(value: string, expression: string): Promise<string> {
  const expr = jsonata(expression);

  // Try parsing value as JSON first (for structured inputs like subnet maps).
  // Only parse objects and arrays; leave primitives as strings so the expression
  // can do its own type conversion.
  let input: unknown;
  try {
    const parsed = JSON.parse(value);
    if (typeof parsed === "object" && parsed !== null) {
      input = parsed;
    } else {
      input = value;
    }
  } catch {
    // Not JSON, use as plain string
    input = value;
  }

  const result = await expr.evaluate(input);
  return JSON.stringify(result);
}

/**
 * Apply all transforms to a resolved inputs map.
 * Returns a new map with transformed values (JSON-encoded) for inputs that
 * have transforms, and original string values for those that don't.
 */
export async function applyTransforms(
  inputs: Record<string, string>,
  transforms: Record<string, string>,
): Promise<Record<string, string>> {
  const result: Record<string, string> = {};

  for (const [varName, value] of Object.entries(inputs)) {
    const expr = transforms[varName];
    if (expr) {
      result[varName] = await applyTransform(value, expr);
    } else {
      result[varName] = value;
    }
  }

  return result;
}
