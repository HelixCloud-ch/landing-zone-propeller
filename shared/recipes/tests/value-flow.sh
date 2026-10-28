#!/usr/bin/env bash
# Contract test for how input/output values cross the shell layers:
#   workload-parameters aggregator (PROPELLER_INPUT_* -> .propeller-outputs.json)
#   _propeller-vars (PROPELLER_INPUT_* -> _propeller.auto.tfvars.json)
# The Lambda side (SSM blob encoding) is covered by autopilot/src/services/ssm.test.ts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected $2, got $3"; fail=1; fi
}

# Values as they arrive in CodeBuild: maps/lists JSON-encoded, scalars raw,
# JSONata scalar results JSON-quoted.
export PROPELLER_INPUT_ou_ids='{"Workloads/Test":"ou-ab12-cd34"}'
export PROPELLER_INPUT_subnet_ids='["subnet-a","subnet-b"]'
export PROPELLER_INPUT_operations_account_id='012345678901'
export PROPELLER_INPUT_tgw_id='tgw-0123456789abcdef0'
export PROPELLER_INPUT_eni_id='"eni-123"'

# ── Aggregator: values pass through verbatim ──
cp "$ROOT/landing-zone/projects/workload-parameters/justfile" "$TMP/justfile"
(cd "$TMP" && just apply >/dev/null)
out="$TMP/.propeller-outputs.json"
check "aggregator keeps map as JSON string" "string" "$(jq -r '.ou_ids | type' "$out")"
check "aggregator keeps map content" "$PROPELLER_INPUT_ou_ids" "$(jq -r '.ou_ids' "$out")"
check "aggregator keeps account id leading zero" "012345678901" "$(jq -r '.operations_account_id' "$out")"
check "aggregator keeps scalar" "tgw-0123456789abcdef0" "$(jq -r '.tgw_id' "$out")"

# ── _propeller-vars: maps/lists decoded, scalars kept as strings ──
mkdir -p "$TMP/proj/terraform"
printf 'import "%s/shared/recipes/terraform.just"\n' "$ROOT" > "$TMP/proj/justfile"
(cd "$TMP/proj" && AWS_ACCOUNT_ID=111111111111 AWS_REGION=eu-central-2 \
  PROPELLER_NAMESPACE=test PROJECT_NAME=proj just _propeller-vars >/dev/null)
vars="$TMP/proj/terraform/_propeller.auto.tfvars.json"
check "tfvars decodes map" "object" "$(jq -r '.ou_ids | type' "$vars")"
check "tfvars map value" "ou-ab12-cd34" "$(jq -r '.ou_ids["Workloads/Test"]' "$vars")"
check "tfvars decodes list" "array" "$(jq -r '.subnet_ids | type' "$vars")"
check "tfvars keeps account id as string" "012345678901" "$(jq -r '.operations_account_id' "$vars")"
check "tfvars unwraps JSONata scalar" "eni-123" "$(jq -r '.eni_id' "$vars")"

exit $fail
