#!/usr/bin/env bash
# Build one venv per enabled python env at /opt/propeller/python/<key>/.venv,
# from the env's uv.lock, and record the Python version it uses. The env files
# (pyproject.toml, uv.lock, .python-version) are kept next to the venv.
# Usage: python.sh MANIFEST SOURCES   (SOURCES holds <key>/ dirs from the renderer)
set -euo pipefail
manifest="$1" sources="$2"
. "$(dirname "$0")/lib.sh"

root=/opt/propeller/python

keys="$(enabled_keys "$manifest" python_envs)"
for key in $keys; do
  dest="$root/$key"
  echo "python env $key"
  mkdir -p "$dest"
  cp -a "$sources/$key/." "$dest/"
  # --locked: fail if uv.lock does not match pyproject.toml.
  # --no-install-project: install the dependencies only, never the env itself.
  uv sync --project "$dest" --locked --no-dev --no-install-project --no-cache --compile-bytecode --link-mode copy
  python_version="$("$dest/.venv/bin/python" -c 'import platform; print(platform.python_version())')"
  set_resolved "$manifest" python_envs "$key" python "$python_version"
done
