#!/usr/bin/env bash
# Assert that the tool versions in versions.env match the fallback defaults in
# the buildspec (autopilot/src/constants.ts). Run locally or from CI.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$REPO_ROOT"

source platform/projects/deploy-runner-image/versions.env
CONSTANTS=autopilot/src/constants.ts
fail=0

check() {
  local key="$1" expected="$2"
  if grep -qF "\"${expected}\"" "$CONSTANTS"; then
    echo "ok:   ${key}=${expected}"
  else
    echo "MISMATCH: ${key}=${expected} (from versions.env) not found in ${CONSTANTS}"
    fail=1
  fi
}

check TF_VERSION   "$TERRAFORM_VERSION"
check JUST_VERSION "$JUST_VERSION"

if [[ "$fail" -ne 0 ]]; then
  echo "Update the matching values in ${CONSTANTS} to fix the mismatch."
  exit 1
fi
