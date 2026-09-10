# MSK Connect Plugin Artifact

Builds the Debezium MSK Connect plugin artifacts and uploads them to a
destination S3 bucket. This is a non-Terraform, `just`-driven build project.

It produces the MariaDB and Oracle Debezium plugin artifacts: ZIP archives of
the connector JARs and the [`msk-config-providers`](https://github.com/aws-samples/msk-config-providers)
config-provider JARs, flattened into a single directory so Kafka Connect finds
them. The Oracle flavour additionally carries the Oracle JDBC driver (bundled in
the upstream connector tarball) together with the unmodified [Oracle Free Use
Terms and Conditions](https://www.oracle.com/downloads/licenses/oracle-free-license.html)
license text. Each artifact is uploaded under a version-qualified key so a
connector upgrade is a reviewable diff, never a silent overwrite.

## What it produces

For each requested flavour, one ZIP object in the destination bucket at
`<key_prefix>debezium-<flavour>-<DEBEZIUM_VERSION>.zip`, containing:

- **mariadb** — the Debezium MariaDB connector JARs plus the config-provider JARs.
- **oracle** — the Debezium Oracle connector JARs (which already bundle
  `ojdbc8` and `orai18n`) plus the config-provider JARs and the Oracle Free Use
  Terms license text.

The build downloads the pinned Debezium connector tarballs from
[Maven Central](https://repo1.maven.org/maven2/io/debezium/) and the
config-providers "with-dependencies" release from its
[GitHub release](https://github.com/aws-samples/msk-config-providers/releases/tag/r0.4.0),
flattens every JAR into one directory, zips it, and uploads it. A download
failure aborts the build without uploading a partial artifact.

The build is pure bash, driven entirely from the `justfile`. It relies only on
tools present on the `Egress_Runner` image — the `aws` CLI (`aws s3api` /
`aws s3`), `curl`, `tar`, `unzip`, `zip` and `jq`. There is no Python or AWS SDK
dependency. Input and version resolution lives in a private `_resolve` recipe
that both `plan` and `apply` evaluate.

## Inputs

Inputs arrive as `PROPELLER_INPUT_*` environment variables. Nothing about the
destination bucket is hardcoded.

| Input | Required | Meaning |
| ----- | :------: | ------- |
| `PROPELLER_INPUT_bucket` | yes | Destination S3 bucket for the artifacts. Never hardcoded — always supplied by the consumer. |
| `PROPELLER_INPUT_key_prefix` | no | Key prefix under which artifacts are written. Default `debezium/`. |
| `PROPELLER_INPUT_flavours` | no | Flavours to build, space- or comma-separated. Default `mariadb oracle` (both). |
| `PROPELLER_INPUT_debezium_version` | no | Override the Debezium version for a one-off build. Defaults to the pin in `versions.env`. |
| `PROPELLER_INPUT_config_providers_version` | no | Override the msk-config-providers version for a one-off build. Defaults to the pin in `versions.env`. |
| `PROPELLER_INPUT_ojdbc_version` | no | Override the Oracle JDBC driver version for a one-off build. Defaults to the pin in `versions.env`. |
| `PROPELLER_INPUT_maven_central_url` | no | Base URL for the Debezium connector tarballs. Defaults to the value in `versions.env`; override to use an internal mirror. |
| `PROPELLER_INPUT_config_providers_releases_url` | no | Base URL for the msk-config-providers release downloads. Defaults to the value in `versions.env`; override to use an internal mirror. |
| `PROPELLER_INPUT_oracle_license_url` | no | Source URL for the Oracle Free Use Terms license text. Defaults to the value in `versions.env`; override to use an internal copy. |

The pinned artifact versions live in `versions.env` — `DEBEZIUM_VERSION`,
`CONFIG_PROVIDERS_VERSION`, `OJDBC_VERSION`. That file is the committed source of
truth and the default: the normal way to change a version is a deliberate,
reviewable diff to `versions.env`, so a connector upgrade never happens by
accident.

The three optional `PROPELLER_INPUT_*_version` inputs are an escape hatch for a
one-off build without editing the file — each defaults to the `versions.env` pin
and, when supplied, must itself be an explicit concrete version, never "latest".

The download base URLs are likewise pinned in `versions.env`
(`MAVEN_CENTRAL_URL`, `CONFIG_PROVIDERS_RELEASES_URL`, `ORACLE_LICENSE_URL`) and
overridable per build via the matching `PROPELLER_INPUT_*_url` inputs. A consumer
behind an internal Maven mirror, a GitHub Enterprise host, or an offline copy of
the license text can point the build at those sources without forking the
project — nothing about where artifacts are fetched from is hardcoded beyond an
overridable default.

## Outputs

A **single** field, written to `.propeller-outputs.json`:

| Output | Consumed by | Shape |
| ------ | ----------- | ----- |
| `flavours_json` | `msk-connect-plugin` | JSON object mapping each flavour to `{file_key, object_version}`. |

Example:

```json
{
  "mariadb": { "file_key": "debezium/debezium-mariadb-2.7.4.Final.zip", "object_version": "abc123" },
  "oracle":  { "file_key": "debezium/debezium-oracle-2.7.4.Final.zip",  "object_version": "def456" }
}
```

## Idempotency and `destroy`

- **`plan`** reports what it would build and the keys it would write, without
  writing anything to the bucket.
- **`apply`** skips the rebuild and re-upload when the version-qualified object
  already exists at its key; it emits the existing key and object version
  unchanged. Object versions therefore do not churn on re-runs.
- **`destroy`** is a deliberate no-op. Artifact lifecycle belongs to the bucket
  (its versioning and lifecycle policy), not to this project — removing an
  artifact would break any plugin still referencing it.

## What does NOT belong here

- **Registering the plugin** — that is `msk-connect-plugin`, which turns
  `flavours_json` into `aws_mskconnect_custom_plugin` resources.
- **Building anything not pinned** — every artifact version comes from
  `versions.env`; there are no "latest" references.
- **Hardcoding a bucket** — the destination bucket is always an input.

## References

- [Debezium Release Series 2.7](https://debezium.io/releases/2.7/)
- [aws-samples/msk-config-providers — release r0.4.0](https://github.com/aws-samples/msk-config-providers/releases/tag/r0.4.0)
- [Oracle Free Use Terms and Conditions](https://www.oracle.com/downloads/licenses/oracle-free-license.html)
