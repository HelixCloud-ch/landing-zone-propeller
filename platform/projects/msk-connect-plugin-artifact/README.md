# MSK Connect Plugin Artifact

Builds the Debezium MSK Connect plugin artifacts and uploads them to a
destination S3 bucket. This is a non-Terraform, `just`-driven build project.

It produces the MariaDB and Oracle Debezium plugin artifacts: ZIP archives of
the connector JARs and the [`msk-config-providers`](https://github.com/aws-samples/msk-config-providers)
config-provider JARs, flattened into a single directory so Kafka Connect finds
them. The Oracle flavour additionally carries the Oracle JDBC driver (bundled in
the upstream connector tarball) together with the unmodified [Oracle Free Use
Terms and Conditions](https://www.oracle.com/downloads/licenses/oracle-free-license.html)
license text.

Every supported version of every requested flavour is built, each under its own
version-qualified key. That is deliberate: an MSK Connect custom plugin
[cannot be updated in place](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-plugins.html),
so a version bump has to become a *new* plugin rather than a mutation of the
existing one. Artifacts are therefore additive, and so are the plugins built
from them.

## The manifest

`versions.json` is the committed source of truth: a **catalogue** of vetted
Debezium versions per flavour, each carrying its compatibility envelope, an
`enabled` flag, and one marked `default`.

```json
{
  "config_providers": {
    "release_tag": "r0.4.0",
    "asset": "msk-config-providers-0.4.0-with-dependencies.zip"
  },
  "urls": { "maven_central": "https://repo1.maven.org/maven2", "...": "..." },
  "flavours": {
    "mariadb": {
      "default": "2.7.4.Final",
      "supported": {
        "2.7.4.Final": {
          "enabled": true,
          "java": "11+",
          "min_kafka_connect": "2.7.1",
          "built_against_kafka_connect": "3.7.0",
          "tested_engine_versions": ["11.4"],
          "source": "https://debezium.io/releases/2.7/",
          "release_notes": "https://debezium.io/releases/2.7/release-notes"
        },
        "3.6.2.Final": { "enabled": false, "...": "..." }
      }
    }
  }
}
```

**Only enabled versions are built.** That is what makes the catalogue cheap:
adding a version records that it has been checked against the compatibility
axes below and pins its download coordinates, but costs nothing — no artifact,
no S3 object, no custom plugin — until someone opts in. Disabled entries are
still printed by `plan`, so the vetted-but-not-built set stays discoverable
instead of living in a commit message.

`enabled` is mandatory and must be a literal `true` or `false`. There is no
default, because a defaulted flag would mean cataloguing a version silently
starts building it.

The per-version metadata is the **compatibility envelope**: `source` cites the
Debezium release series page (its *tested versions* table — Debezium publishes
no support contract, and the release index notes a connector may also work
against versions not listed), and `release_notes` cites that exact patch's own
release notes, which name the Kafka Connect version it was actually built and
tested against — a stricter, and independently moving, number than the series
floor. See [Choosing a version](#choosing-a-version) for why both matter. There
is no machine-readable feed for either, so the envelope is maintained by hand;
both URLs are mandatory and `plan` fails without either.

Changing versions is a deliberate, reviewable diff to this file. There are no
"latest" references and `plan` rejects one.

### Enabling a version

1. Add it under `supported` with `enabled: false` and a full envelope
   transcribed from its release series page. Confirm the artifact exists at
   `<maven_central>/io/debezium/debezium-connector-<flavour>/<version>/debezium-connector-<flavour>-<version>-plugin.tar.gz`.
2. Flip `enabled` to `true` and run the artifact project. The new ZIP is built
   alongside the existing ones; nothing is replaced.
3. Register it (`msk-connect-plugin`) and cut the connector over.
4. Only then move `default` onto it.

`default` must itself be enabled — `plan` rejects a default that is disabled or
absent from `supported`, so a default can never point at a version with no
plugin behind it. At least one version per flavour must be enabled.

For a one-off build without editing the file, pass the whole manifest as
`PROPELLER_INPUT_manifest_json`; it is validated identically.

### Removing a version

Setting `enabled: false` stops it being built and drops it from `plugins_json`.
Deleting the key removes it from the catalogue entirely. Either way the S3 object
survives, because `destroy` here is a no-op and artifact lifecycle belongs to the
bucket.

The consequential half of the rule lives in
[`msk-connect-plugin`](../msk-connect-plugin/README.md), which destroys the
corresponding custom plugin: a version may only be disabled or removed once the
bump has run at least once and no connector still references that plugin.

Keep the artifact for as long as the plugin should stay reproducible. MSK
Connect copies the ZIP's contents when the plugin is created and keeps no link
to the object, so deleting an artifact does not break a live plugin, but it does
make that plugin impossible to recreate from state.

## Choosing a version

Three constraints stack, and a version has to satisfy all three.

**1. What MSK Connect runs.** Kafka Connect `2.7.1` on Java 11, or `3.7.x` on
Java 17 — those two, nothing newer
([custom plugin runtime table](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-plugins.html),
[3.7 launch](https://aws.amazon.com/about-aws/whats-new/2024/12/amazon-msk-connect-apache-kafka-connect-version-3-7/)).
The connector module defaults to `3.7.x`, so the Java 17 runtime is the one that
matters in practice.

**2. What the Debezium series' floor requires.** The 2.7 series needs Java 11+
and Kafka Connect 2.x/3.x. Every 3.x series needs Java 17+ and Kafka Connect 3.1
or later. Both floors fit inside MSK Connect's `3.7.x`, so on the *floor* alone
AWS is not the limiting factor. Only `Final` releases are catalogued; a series
marked *development* on debezium.io is not — as of this writing that excludes
3.7.

**2b. What the Debezium patch was actually built and tested against.** The
series page's Kafka Connect line is a floor, not a ceiling, and each patch's own
release notes name the exact version it was built and tested against — which
climbs release over release, independently of the series floor:

| Version | Built against / tested with | vs. MSK Connect's 3.7.x ceiling |
| --- | --- | --- |
| 2.7.4.Final | Kafka Connect 3.7.0 | matches exactly |
| 3.5.2.Final | Kafka Connect 4.1.2 | past it |
| 3.6.2.Final | Kafka Connect 4.3.0 | past it |

`2.7.4.Final` was built against the exact version MSK Connect's newer runtime
offers. `3.5.2.Final` and `3.6.2.Final` clear the stated floor but were built
against Kafka 4.x, past what MSK Connect runs — an untested combination, not a
documented failure. This is why they are catalogued (`enabled: false`) rather
than omitted, and why `default` stays on `2.7.4.Final` until someone verifies
one empirically against a real MSK Connect `3.7.x` worker and flips `enabled`.
`built_against_kafka_connect` and `release_notes` capture this per version so
the next reviewer sees the delta without re-deriving it.

**3. What the source database is.** The intersection of Debezium's tested list
and what RDS actually offers (this axis is orthogonal to axis 2b — it constrains
which version to promote to default among those already verified against MSK
Connect):

| Flavour | Debezium 2.7 tests | Debezium 3.5 / 3.6 test | On RDS today | Usable intersection |
| --- | --- | --- | --- | --- |
| MariaDB | 11.4.3 | 11.4.x, 11.7.x | 10.11, 11.4, 11.8, 12.3 | **11.4** |
| Oracle | 12c, 19c, 21c | 19c, 21c, 23ai, 26ai | 19c, 21c, 26ai | 19c, 21c (2.7) · **+26ai** (3.x) |

MariaDB 11.4 is the only line tested by every catalogued version *and* offered by
RDS; 11.7 is not an RDS line, and 11.8 and 12.3 are ahead of Debezium's matrix.
For Oracle, only the 3.x series reaches 26ai, which matters because 21c is an
Innovation Release [ending July 2027](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_UpgradeDBInstance.Oracle.21c-end-of-support.html)
while 19c and 26ai are the Long Term Support releases.

RDS MariaDB 10.11 is fully supported by AWS (standard support to February 2028)
but is tested by no Debezium series. The pressure to move to 11.4 comes entirely
from Debezium, not from AWS.

### msk-config-providers

`release_tag` and `asset` are given explicitly rather than derived from a version
number, because the release naming is not stable: `r0.4.0` carries an `r` prefix
and ships a `-with-dependencies.zip`, while `v0.5.0` drops the prefix and ships
an `-all.jar` uber jar. Deriving either would break silently on a bump. The build
accepts both shapes — a `.zip` is unpacked, a `.jar` is taken as the payload.

### Removing a version

Deleting a key from `supported` stops the version being built; the S3 object
survives, because `destroy` here is a no-op and artifact lifecycle belongs to
the bucket. The consequential half of the rule lives in
[`msk-connect-plugin`](../msk-connect-plugin/README.md), which destroys the
corresponding custom plugin — a version may only be removed once the bump has
run at least once and no connector still references that plugin.

Keep the artifact for as long as the plugin should stay reproducible. MSK
Connect copies the ZIP's contents when the plugin is created and keeps no link
to the object, so deleting an artifact does not break a live plugin, but it does
make that plugin impossible to recreate from state.

## Inputs

Inputs arrive as `PROPELLER_INPUT_*` environment variables. Nothing about the
destination bucket is hardcoded.

| Input | Required | Meaning |
| ----- | :------: | ------- |
| `PROPELLER_INPUT_bucket` | yes | Destination S3 bucket for the artifacts. Never hardcoded — always supplied by the consumer. |
| `PROPELLER_INPUT_key_prefix` | no | Key prefix under which artifacts are written. Default `debezium/`. |
| `PROPELLER_INPUT_flavours` | no | Restrict to a subset of the manifest's flavours, space- or comma-separated. Default: every declared flavour. Orthogonal to `enabled`, which selects versions. |
| `PROPELLER_INPUT_manifest_json` | no | Replaces the whole manifest for a one-off build. Validated exactly as `versions.json` is. |
| `PROPELLER_INPUT_maven_central_url` | no | Base URL for the Debezium connector tarballs. Overrides the manifest; use for an internal Maven mirror. |
| `PROPELLER_INPUT_config_providers_releases_url` | no | Base URL for the msk-config-providers release downloads. Overrides the manifest; use for a GitHub Enterprise host. |
| `PROPELLER_INPUT_oracle_license_url` | no | Source URL for the Oracle Free Use Terms license text. Overrides the manifest; use for an internal copy. |

The three URL overrides exist because they point at a *different source for the
same bytes* — a mirror, not a different artifact. There is deliberately no
per-version override: the S3 key encodes the version, so overriding a version
piecemeal would write different content under a key that already exists, which
the idempotency skip would then hide. Version changes go through the manifest.

## Outputs

Two fields, written to `.propeller-outputs.json`. Each is one JSON object
encoded as a string, because a propeller input reads exactly one output field
and each map has to travel whole.

| Output | Consumed by | Shape |
| ------ | ----------- | ----- |
| `plugins_json` | `msk-connect-plugin` (`plugins`) | `"<flavour>-<version>"` to `{file_key, object_version}`, enabled versions only. |
| `default_versions_json` | `msk-connect-plugin` (`default_versions`) | flavour to its default version. |

```json
{
  "plugins_json": "{\"mariadb-2.7.4.Final\":{\"file_key\":\"debezium/debezium-mariadb-2.7.4.Final.zip\",\"object_version\":\"abc123\"}}",
  "default_versions_json": "{\"mariadb\":\"2.7.4.Final\"}"
}
```

`object_version` is empty when the destination bucket is not versioned.

## Idempotency and `destroy`

- **`plan`** validates the manifest, prints the whole catalogue — enabled and
  disabled — with each version's compatibility envelope, and contacts nothing.
  Every validation failure is reported in one message rather than one at a time.
- **`apply`** skips the rebuild and re-upload when the version-qualified object
  already exists at its key; it emits the existing key and object version
  unchanged. Object versions therefore do not churn on re-runs.
- **`destroy`** is a deliberate no-op. Artifact lifecycle belongs to the bucket
  (its versioning and lifecycle policy), not to this project — removing an
  artifact would break any plugin still referencing it.

A download failure aborts the build for that flavour without uploading, as does
an archive that yields no JARs.

## Runtime dependencies

Pure bash driven from the `justfile`: the `aws` CLI (`aws s3api`), `curl`, `tar`,
`unzip`, `zip` and `jq`. No Python, no AWS SDK. Manifest resolution and
validation live in a private `_resolve` recipe that emits one JSON document,
which both `plan` and `apply` query — so the two agree on the build matrix by
construction. The validation logic itself lives in [`resolve.jq`](resolve.jq)
as a set of named `def`s (one per config-providers check, one per catalogued
version, one per flavour, composed into the whole-manifest check) rather than
inline in the recipe. `plan`'s catalogue listing is similarly factored into
[`print_catalogue.jq`](print_catalogue.jq).

## What does NOT belong here

- **Registering the plugin** — that is `msk-connect-plugin`, which turns
  `plugins_json` into `aws_mskconnect_custom_plugin` resources.
- **Building anything not enabled in the manifest** — every version comes from
  `versions.json`; there are no "latest" references.
- **Hardcoding a bucket** — the destination bucket is always an input.
- **Enforcing the compatibility envelope** — this project transcribes and
  displays it. Checking a source database against `tested_engine_versions`
  belongs to `cdc-prepare-mariadb`; checking `min_kafka_connect` against the
  connector's Kafka Connect version belongs to `msk-connect-debezium`.

## References

- [AWS — MSK Connect custom plugins](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-plugins.html)
- [Debezium Release Series 2.7](https://debezium.io/releases/2.7/)
- [Debezium releases index](https://debezium.io/releases/)
- [aws-samples/msk-config-providers — release r0.4.0](https://github.com/aws-samples/msk-config-providers/releases/tag/r0.4.0)
- [Oracle Free Use Terms and Conditions](https://www.oracle.com/downloads/licenses/oracle-free-license.html)
