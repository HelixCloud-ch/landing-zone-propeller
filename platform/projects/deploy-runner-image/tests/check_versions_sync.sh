#!/usr/bin/env bash
# Assert that the tool versions in image.yaml match the fallback defaults in
# the buildspec (autopilot/src/constants.ts). Run locally or from CI.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$REPO_ROOT"

project=platform/projects/deploy-runner-image
manifest="$(uv run --quiet --project "$project/renderer" --frozen --no-dev \
  python "$project/renderer/render.py" --manifest "$project/image.yaml" show)"
CONSTANTS=autopilot/src/constants.ts

fail=0
check() {
  local var="$1" component="$2" expected
  expected="$(jq -r --arg k "$component" '.binaries[$k].version' <<<"$manifest")"
  if grep -qF "${var}: \"${expected}\"" "$CONSTANTS"; then
    echo "ok:   ${var}=${expected}"
  else
    echo "MISMATCH: ${var}=${expected} (from image.yaml, binaries.${component}) not found in ${CONSTANTS}"
    fail=1
  fi
}

check TF_VERSION   terraform
check JUST_VERSION just
check UV_VERSION   uv

# The image project's own uv fallback (used before the buildspec has the guard).
uv_version="$(jq -r '.binaries.uv.version' <<<"$manifest")"
if grep -qF "_uv_version := \"${uv_version}\"" "$project/justfile"; then
  echo "ok:   _uv_version=${uv_version} ($project/justfile)"
else
  echo "MISMATCH: _uv_version in $project/justfile is not ${uv_version}"
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Update the matching values in ${CONSTANTS} to fix the mismatch."
  exit 1
fi
