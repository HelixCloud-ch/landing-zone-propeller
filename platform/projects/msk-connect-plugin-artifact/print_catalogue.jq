# print_catalogue.jq — human-readable catalogue listing for `just plan`.
#
# Invoked as: jq -r -f print_catalogue.jq <<<"$resolved"
#
# Input (stdin): the resolved document produced by resolve.jq (specifically
# its `.catalogue` array). Output: one multi-line block per catalogued
# version — enabled/disabled marker, default marker, and its compatibility
# envelope, so a reviewer sees the same three axes documented in README.md
# (MSK Connect's own ceiling, the Debezium floor, and the exact Kafka Connect
# version the release was built/tested against) without re-deriving them.

def catalogue_line($entry):
  "    " + (if $entry.enabled then "[x]" else "[ ]" end) + " " + $entry.plugin_key
    + (if $entry.is_default then "  (default)" else "" end),
  "        key:      " + $entry.file_key,
  "        floor:    Java " + $entry.java + ", Kafka Connect >= " + $entry.min_kafka_connect,
  "        built vs: Kafka Connect " + $entry.built_against_kafka_connect
    + " (MSK Connect caps at 3.7.x — treat > 3.7 as unverified on MSK Connect)",
  "        tested:   " + ($entry.tested_engine_versions | join(", ")),
  "        source:   " + $entry.source,
  "        notes:    " + $entry.release_notes;

.catalogue[] | catalogue_line(.)
