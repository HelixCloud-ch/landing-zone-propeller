#!/usr/bin/env bash
# Run the enabled scripts, in key order. Scripts run as root, last,
# with network access. Each runs in its own empty working directory.
# Usage: scripts.sh MANIFEST SOURCES   (SOURCES holds <key> files from the renderer)
set -euo pipefail
manifest="$1" sources="$2"
. "$(dirname "$0")/lib.sh"

keys="$(enabled_keys "$manifest" scripts)"
for key in $keys; do
  echo "script $key"
  work="$(mktemp -d)"
  (cd "$work" && "$sources/$key" < /dev/null)
  rm -rf "$work"
done
