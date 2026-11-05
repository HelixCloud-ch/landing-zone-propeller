#!/usr/bin/env bash
#
# Tests py-run (shared/recipes/python.just) on a runner without a baked env:
# uv builds the env from the bundle and runs the command in it. This is the
# path a stock CodeBuild image with internet access uses. The baked, offline
# path is tested by `just test-image`.
#
# Needs uv and internet access (PyPI, and a uv-managed Python download).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# Physical path: on macOS the temp dir is behind a symlink (/var -> /private/var).
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

fail=0
pass() { echo "ok   $1"; }
failf() { echo "FAIL $1"; fail=1; }

# Bundle-shaped copy: the same relative paths py-run sees in CodeBuild.
mkdir -p "$WORK/platform/projects" "$WORK/platform/shared" "$WORK/shared"
cp -R "$ROOT/platform/projects/python-smoke" "$WORK/platform/projects/"
cp -R "$ROOT/platform/shared/python" "$WORK/platform/shared/"
cp -R "$ROOT/shared/recipes" "$WORK/shared/"
project="$WORK/platform/projects/python-smoke"

# Use a uv-managed interpreter from a test-only install dir, not whatever
# Python the host has (an old pre-release would also match .python-version).
# dist/ is gitignored and removed by `just clean`; reruns reuse the download.
export UV_PYTHON_PREFERENCE=only-managed UV_PYTHON_INSTALL_DIR="$ROOT/dist/test-python" UV_NO_PROGRESS=1

if (cd "$project" && just apply >"$WORK/apply.log" 2>&1); then
  pass "py-run builds the env from the bundle and runs main.py"
else
  cat "$WORK/apply.log"
  failf "py-run apply failed"
fi

outputs="$project/.propeller-outputs.json"
want_pyyaml="$(sed -n 's/.*"pyyaml==\(.*\)".*/\1/p' "$ROOT/platform/shared/python/python-smoke/pyproject.toml")"
want_python="$(tr -d '[:space:]' < "$ROOT/platform/shared/python/python-smoke/.python-version")"
if [[ -f "$outputs" ]]; then
  [[ "$(jq -r .pyyaml_version "$outputs")" == "$want_pyyaml" ]] \
    && pass "locked PyYAML version ($want_pyyaml)" || failf "PyYAML version: $(jq -r .pyyaml_version "$outputs")"
  [[ "$(jq -r .python_version "$outputs")" == "$want_python"* ]] \
    && pass "Python from .python-version ($want_python)" || failf "Python version: $(jq -r .python_version "$outputs")"
  [[ "$(jq -r .interpreter "$outputs")" == "$WORK/platform/shared/python/python-smoke/.venv/"* ]] \
    && pass "env built in the bundle" || failf "interpreter: $(jq -r .interpreter "$outputs")"
else
  failf "no .propeller-outputs.json"
fi

exit "$fail"
