#!/usr/bin/env bash
# Download the enabled binaries for ARCH, verify each against its upstream
# checksum file, and write it to OUT/bin/<key>. Write the build facts (the URL
# and the verified sha256) to OUT/resolved.json, for finalize.sh.
# Usage: binaries.sh MANIFEST ARCH OUT
set -euo pipefail
manifest="$1" arch="$2" out="$3"
. "$(dirname "$0")/lib.sh"

mkdir -p "$out/bin"
work="$(mktemp -d)"
resolved='{}'

# fetch URL FILE: https only (also on redirects), fail on HTTP errors, retry
# transient errors (timeouts, 408, 429, 5xx).
fetch() {
  curl --proto "=https" --proto-redir "=https" --retry 3 --retry-delay 2 -fsSL -o "$2" "$1"
}

# checksum_for FILE SUMS: the hash for FILE in a checksum file. Handles the two
# upstream formats: "<hash>  <file>" lines (also "*<file>"), or a bare hash.
checksum_for() {
  local file="$1" sums="$2" hash
  hash="$(awk -v f="$file" '{ n = $2; sub(/^\*/, "", n) } NF >= 2 && n == f { print $1; exit }' "$sums")"
  if [[ -z "$hash" && "$(wc -w < "$sums")" -eq 1 ]]; then
    hash="$(tr -d '[:space:]' < "$sums")"
  fi
  printf '%s' "$hash"
}

keys="$(enabled_keys "$manifest" binaries)"
for key in $keys; do
  artifact="$(jq -c --arg k "$key" --arg a "$arch" '.binaries[$k].artifacts[$a]' "$manifest")"
  url="$(jq -r .url <<<"$artifact")"
  checksum_url="$(jq -r .checksum_url <<<"$artifact")"
  file="$(jq -r .file <<<"$artifact")"
  extract="$(jq -r '.extract // empty' <<<"$artifact")"

  echo "binary $key: $url"
  fetch "$url" "$work/$file"
  fetch "$checksum_url" "$work/$file.sums"
  expected="$(checksum_for "$file" "$work/$file.sums")"
  if [[ -z "$expected" ]]; then
    echo "binary $key: no checksum for $file in $checksum_url" >&2
    exit 1
  fi
  echo "$expected  $work/$file" | sha256sum -c --quiet -

  case "$file" in
    *.zip) unzip -p "$work/$file" "$extract" > "$out/bin/$key" ;;
    *.tar.gz | *.tgz) tar -xzf "$work/$file" -O "$extract" > "$out/bin/$key" ;;
    *) cp "$work/$file" "$out/bin/$key" ;;
  esac
  [[ -s "$out/bin/$key" ]] || { echo "binary $key: $extract is empty or missing in $file" >&2; exit 1; }
  chmod 0755 "$out/bin/$key"

  resolved="$(jq --arg k "$key" --arg u "$url" --arg h "$expected" \
    '.[$k] = {url: $u, sha256: $h}' <<<"$resolved")"
done
printf '%s\n' "$resolved" > "$out/resolved.json"
rm -rf "$work"
