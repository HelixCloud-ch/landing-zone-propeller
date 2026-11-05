#!/usr/bin/env bash
# Check the image before it is pushed, then complete the image's own manifest.
#
# Checks: each enabled binary must be an ELF executable for ARCH, and its
# `check` command, if any, must succeed. This catches a wrong arch map or a
# binary that does not run on the base image.
#
# Manifest: add the binaries' build facts (from the fetch stage), the base
# image digest, and build info; drop the per-arch download list, which the
# `resolved` objects replace.
# Usage: finalize.sh MANIFEST PROPELLER_VERSION ARCH BASE_DIGEST FETCH_RESOLVED
set -euo pipefail
manifest="$1" version="$2" arch="$3" base_digest="$4" fetch_resolved="$5"
. "$(dirname "$0")/lib.sh"

# ELF e_machine values: x86-64 = 62, AArch64 = 183.
case "$arch" in
  amd64) want_machine=62 ;;
  arm64) want_machine=183 ;;
  *) echo "finalize: unsupported arch $arch" >&2; exit 1 ;;
esac

fail=0
keys="$(enabled_keys "$manifest" binaries)"
for key in $keys; do
  bin="/usr/local/bin/$key"
  magic="$(od -An -c -N 4 "$bin" | tr -d ' \n')"
  machine="$(od -An -t u2 -j 18 -N 2 "$bin" | tr -d ' \n')"
  if [[ "$magic" != '177ELF' ]]; then
    echo "binary $key: not an ELF executable" >&2
    fail=1
    continue
  fi
  if [[ "$machine" != "$want_machine" ]]; then
    echo "binary $key: built for ELF machine $machine, not $arch" >&2
    fail=1
    continue
  fi
  check="$(field "$manifest" binaries "$key" check)"
  if [[ -n "$check" ]]; then
    if out="$(bash -c "$check" 2>&1)"; then
      echo "binary $key: ok ($(head -1 <<<"$out"))"
    else
      echo "$out" >&2
      echo "binary $key: check failed: $check" >&2
      fail=1
    fi
  else
    echo "binary $key: ok (ELF $arch, no check command)"
  fi
done
(( fail == 0 )) || exit 1

tmp="$(mktemp)"
jq --slurpfile fetched "$fetch_resolved" \
   --arg v "$version" --arg a "$arch" --arg d "$base_digest" '
  .binaries |= with_entries(
    del(.value.artifacts)
    | if $fetched[0][.key] then .value.resolved = $fetched[0][.key] else . end)
  | if $d != "" then .base.resolved = {digest: $d} else . end
  | .build = {propeller_version: $v, arch: $a}
' "$manifest" > "$tmp"
mv "$tmp" "$manifest"
chmod 0644 "$manifest"
