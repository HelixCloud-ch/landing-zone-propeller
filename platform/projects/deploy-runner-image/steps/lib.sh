# shellcheck shell=bash
# Shared helpers for the build steps. Sourced, not executed.

# enabled_keys MANIFEST SECTION: print the keys of the enabled components in
# SECTION, in key order (the renderer writes them sorted). Keys never contain
# whitespace (the renderer enforces it), so callers can use the output as a
# word list: `keys="$(enabled_keys ...)"` stops the step if jq fails, then
# `for key in $keys`.
enabled_keys() {
  jq -r --arg s "$2" '.[$s] // {} | to_entries[] | select(.value.enabled) | .key' "$1"
}

# field MANIFEST SECTION KEY FIELD: print one field of a component, or "".
field() {
  jq -r --arg s "$2" --arg k "$3" --arg f "$4" '.[$s][$k][$f] // empty' "$1"
}

# set_resolved MANIFEST SECTION KEY FIELD VALUE: record a build fact in the
# component's `resolved` object.
set_resolved() {
  local tmp
  tmp="$(mktemp)"
  jq --arg s "$2" --arg k "$3" --arg f "$4" --arg v "$5" \
    '.[$s][$k].resolved[$f] = $v' "$1" > "$tmp"
  mv "$tmp" "$1"
  chmod 0644 "$1"
}
