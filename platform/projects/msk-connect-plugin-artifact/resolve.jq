# resolve.jq — manifest validation and resolution for msk-connect-plugin-artifact.
#
# Invoked by the justfile's `_resolve` recipe as:
#   jq -f resolve.jq --arg bucket ... --arg key_prefix ... \
#     --arg maven_central ... --arg config_providers_releases ... \
#     --arg oracle_license ... --argjson filter '[...]'
#
# Input (stdin): the manifest document — either versions.json or
# PROPELLER_INPUT_manifest_json.
# Output: one JSON object — { bucket, key_prefix, config_providers, urls,
# defaults, catalogue } — consumed by both `plan` and `apply`.
#
# Each `def` below is one named sub-check; `validate_manifest` composes them
# into the single list of error strings that becomes the `error("manifest: ..."
# )` message on failure. Test any def standalone, e.g.:
#   echo '{"release_tag":"","asset":""}' | jq -f resolve.jq -n \
#     'include "resolve"; validate_config_providers(input)'

# ── config_providers: release_tag + asset must be present and unpackable ────
def validate_config_providers($cp):
  [
    (if (($cp.release_tag // "") | length) == 0
     then "config_providers.release_tag is missing" else empty end),
    (if (($cp.asset // "") | length) == 0
     then "config_providers.asset is missing"
     elif (($cp.asset | test("\\.(zip|jar)$")) | not)
     then "config_providers.asset must end in .zip or .jar (the shapes the build can unpack)"
     else empty end)
  ];

# ── one catalogued version: enabled flag + citations ─────────────────────────
def validate_version($flavour; $version; $meta):
  [
    (if ($version | ascii_downcase | test("latest"))
     then $flavour + ": version \"" + $version + "\" must be concrete, not \"latest\""
     else empty end),
    (if ($meta | has("enabled")) and (($meta.enabled | type) == "boolean")
     then empty
     else $flavour + " " + $version
          + ": enabled must be true or false (a catalogued version needs an explicit decision)"
     end),
    (if (($meta.source // "") | length) == 0
     then $flavour + " " + $version
          + ": source URL is missing (cite the Debezium release series page)"
     else empty end),
    (if (($meta.release_notes // "") | length) == 0
     then $flavour + " " + $version
          + ": release_notes URL is missing (cite the exact patch build target for"
          + " Kafka Connect; the series page states only a floor, not what the"
          + " release was actually built against)"
     else empty end)
  ];

# ── one flavour: its supported set is non-empty and its default is sane ─────
def validate_flavour($flavour; $entry):
  ($entry.supported // { }) as $sup
  | [
      (if ($sup | length) == 0
       then $flavour + ": supported is empty" else empty end),
      (if (($entry.default // "") | length) == 0
       then $flavour + ": default is missing"
       elif ($sup | has($entry.default)) | not
       then $flavour + ": default \"" + $entry.default + "\" is not in supported"
       elif ($sup[$entry.default].enabled != true)
       then $flavour + ": default \"" + $entry.default + "\" is not enabled"
       else empty end),
      (if ($sup | length) > 0 and ([$sup[] | select(.enabled == true)] | length) == 0
       then $flavour + ": no supported version is enabled" else empty end)
    ]
    + [ $sup | to_entries[] | validate_version($flavour; .key; .value)[] ];

# ── whole manifest: composes the checks above over the selected flavours ────
def validate_manifest($fl; $cp; $sel):
  (if ($fl | length) == 0 then ["declares no flavours"] else [] end)
  + validate_config_providers($cp)
  + [ $sel[] as $f | select(($fl | has($f)) | not) | "unknown flavour \"" + $f + "\"" ]
  + [ $sel[] as $f | select($fl | has($f)) | validate_flavour($f; $fl[$f])[] ];

# ── the flavour x version cross product, one entry per catalogued version ───
def build_catalogue($fl; $sel; $key_prefix):
  [
    $sel[] as $f
    | ($fl[$f].supported | keys[]) as $v
    | $fl[$f].supported[$v] as $meta
    | {
        flavour: $f,
        version: $v,
        plugin_key: ($f + "-" + $v),
        file_key: ($key_prefix + "debezium-" + $f + "-" + $v + ".zip"),
        enabled: $meta.enabled,
        is_default: ($v == $fl[$f].default),
        java: ($meta.java // ""),
        min_kafka_connect: ($meta.min_kafka_connect // ""),
        built_against_kafka_connect: ($meta.built_against_kafka_connect // ""),
        tested_engine_versions: ($meta.tested_engine_versions // []),
        source: $meta.source,
        release_notes: $meta.release_notes
      }
  ];

# ── main: validate, then resolve into the shape plan/apply consume ──────────
. as $m
| ($m.flavours // { }) as $fl
| ($m.config_providers // { }) as $cp
| (if ($filter | length) == 0 then ($fl | keys) else $filter end) as $sel
| validate_manifest($fl; $cp; $sel) as $errs
| if ($errs | length) > 0
  then error("manifest: " + ($errs | join("; ")))
  else . end
| {
    bucket: $bucket,
    key_prefix: $key_prefix,
    config_providers: {
      release_tag: $cp.release_tag,
      asset: $cp.asset
    },
    urls: {
      maven_central: (if $maven_central == "" then $m.urls.maven_central else $maven_central end),
      config_providers_releases: (if $config_providers_releases == "" then $m.urls.config_providers_releases else $config_providers_releases end),
      oracle_license: (if $oracle_license == "" then $m.urls.oracle_license else $oracle_license end)
    },
    defaults: (reduce $sel[] as $f ( { }; . + { ($f): $fl[$f].default } )),
    catalogue: build_catalogue($fl; $sel; $key_prefix)
  }
