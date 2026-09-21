# MSK Connect Plugin

Registers the Debezium connector artifacts — the ZIP archives already in S3,
built and uploaded by `msk-connect-plugin-artifact` — as MSK Connect custom
plugins, one `aws_mskconnect_custom_plugin` per flavour. This project builds and
uploads nothing: it only turns artifacts that already exist into plugin
resources the connector can reference.

## What it deploys

One custom plugin per entry in `var.plugins`, keyed by full plugin identity
`<flavour>-<version>` (e.g. `mariadb-2.7.4.Final`), named
`debezium-<flavour>-<version>` and pinned to a specific S3 object version. The
version is part of the `for_each` key on purpose: a version bump is a *new key*,
so the new plugin is created alongside the old one rather than replacing it (see
[Idempotency and destroy](#idempotency-and-destroy)). This coexistence is what
lets a connector cut over safely, because MSK Connect refuses to delete a custom
plugin still referenced by a connector. The plugin ARNs are published two ways
— by explicit version and by flavour's default — for the connector project to
consume (see [Outputs](#outputs)).

## Consumer inputs

Wired from the pipeline; nothing about the bucket, keys or versions is
hardcoded.

- **`plugins`** — one input holding the whole map, decoded from the artifact
  project's single `plugins_json` output (the artifact project emits
  version-keyed keys, one per *enabled* catalogue entry — see that project's
  README). It is deliberately one input rather than one per plugin: a
  propeller pipeline input reads exactly one source field, so the per-plugin
  `{file_key, object_version}` pairs travel together as one JSON object. Each
  key is `<flavour>-<version>`; a MariaDB-only consumer supplies a single-key
  map (`{ "mariadb-2.7.4.Final" = { file_key = ... } }`). `object_version` is
  omitted from an entry when the destination bucket is not versioned. A
  version bump adds a new key; remove a key only after no connector references
  it.
- **`default_versions`** — one input holding a flavour-to-version map, decoded
  from the artifact project's `default_versions_json` output (e.g.
  `{ mariadb = "2.7.4.Final" }`). Every value must resolve to a key already
  present in `plugins` — enforced by a `validation` block, so a default can
  never point at a version that was never registered. This is what lets a
  consumer that just wants "the current MariaDB plugin" read
  `default_plugin_arns.mariadb` instead of naming a version explicitly.
- **`artifact_bucket_arn`** — ARN of the S3 bucket holding the artifacts
  referenced by `plugins`.
- **`name_prefix`** — optional, defaults to `debezium` (bare, no trailing
  hyphen). The full plugin name is hyphen-joined as `<name_prefix>-<plugin-key>`
  (the key already carries `<flavour>-<version>`). The composed name is
  validated at plan time to stay within the 128-character MSK Connect custom
  plugin name limit; a `name_prefix` long enough to push any plugin's name past
  128 characters is rejected.

A standalone `terraform apply` without the pipeline supplies the same values as
tfvars; see [`terraform/config.auto.tfvars.example`](terraform/config.auto.tfvars.example)
for the shape.

## Outputs

- **`plugin_arns`** — custom plugin ARNs, a map keyed by `<flavour>-<version>`.
  A consumer naming an explicit version (e.g. mid-cutover, running old and new
  side by side) reads this directly.
- **`plugin_revisions`** — latest plugin revision, keyed by `<flavour>-<version>`,
  for a connector that pins a specific revision.
- **`default_plugin_arns`** — custom plugin ARN of the *default* version, keyed
  by bare flavour (e.g. `default_plugin_arns.mariadb`). This is the field
  `msk-connect-debezium` normally wires from — the pipeline then selects one
  flavour's entry for the single ARN the connector resource takes — because it
  tracks whatever `default_versions` currently says without the pipeline
  wiring needing to change on a version bump.
- **`default_plugin_revisions`** — latest custom plugin revision of the default
  version, keyed by bare flavour.

`plugin_arns` and `default_plugin_arns` differ only in whether the caller names
a version or lets the manifest's `default` decide; both are always populated
from the same `for_each`, so neither can point at a plugin the other doesn't
know about.

## Idempotency and destroy

`plan`, `apply` and `destroy` are the standard Terraform recipes (`tf-plan`,
`tf-apply`, `tf-destroy` from `shared/recipes/terraform.just`); there is no
custom lifecycle logic.

- A **version bump** *adds* a new plugin rather than replacing the in-use one.
  The `for_each` key is `<flavour>-<version>`, so bumping the version yields a
  new key and therefore a new instance
  (`aws_mskconnect_custom_plugin.this["<flavour>-<new-version>"]`) created
  alongside the old one; the old instance
  (`...["<flavour>-<old-version>"]`) is untouched and survives in state. Both
  plugins coexist, which is the point: the connector project
  (`msk-connect-debezium`) can then repoint at the new plugin ARN while the old
  plugin is still referenced, and only once the connector has cut over does the
  consumer remove the old key from `plugins`.
- **Removing a key** destroys just that one plugin. MSK Connect refuses to
  delete a custom plugin still referenced by a connector — this is precisely
  why the version lives in the `for_each` key: coexistence lets the connector
  cut over first, so by the time the old key is removed the plugin is no longer
  in use and the destroy succeeds. Remove a key only after the connector no
  longer references that plugin's ARN.
- **`destroy`** removes all the custom plugin resources. A plugin still in use
  by a connector cannot be deleted, so the connector (`msk-connect-debezium`)
  must be torn down first. See the ordering below.

### State-shape rationale

The `for_each` key is `<flavour>-<version>` specifically so that old and new
plugins coexist across a version bump: a bump maps to a brand-new key rather
than mutating the `name` of an existing instance. A consumer that had already
deployed a *flavour*-keyed version (the previous shape) would need `moved`
blocks to carry existing state addresses to the new keys; because these CDC
projects are pre-first-release / greenfield, there is no existing state to
migrate and no `moved` blocks are shipped.

## Sleep/wake and teardown

No sleep/wake recipe is implemented for any CDC project — the consumer wiring the
pipeline owns that decision, and these projects document the constraints only.
The constraints below concern the CDC chain as a whole and are repeated on every
CDC project's README so the ordering is visible wherever an operator starts:

- The connector must be removed **before** its source database and its Kafka
  cluster.
- Under the framework's MSK sleep semantics, a sleeping
  cluster loses its topics and consumer offsets, so on wake the Topics project
  must run again before the Connector, and Debezium then performs a recovery
  snapshot.
- A sleep outlasting the configured binary-log retention window turns a CDC gap
  into a full re-snapshot.

For this project specifically, a custom plugin holds no runtime state, so it has
no sleep behaviour of its own; the teardown ordering (connector before plugin)
is the only constraint that touches it directly.

## What does NOT belong here

- **Building or uploading artifacts** — that is `msk-connect-plugin-artifact`,
  which produces the ZIPs and emits `plugins_json`. This project only
  registers artifacts that already exist.
- **Creating the connector or its IAM role** — that is `msk-connect-debezium`.
  This project stops at the custom plugin resource.

## References

- [Terraform `aws_mskconnect_custom_plugin`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mskconnect_custom_plugin)
- [AWS — MSK Connect custom plugins](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-plugins.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.64.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_mskconnect_custom_plugin.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mskconnect_custom_plugin) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_artifact_bucket_arn"></a> [artifact\_bucket\_arn](#input\_artifact\_bucket\_arn) | ARN of the S3 bucket holding the connector artifacts referenced by `plugins`. | `string` | n/a | yes |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_default_versions"></a> [default\_versions](#input\_default\_versions) | Default version per flavour, e.g. { mariadb = "2.7.4.Final" }. Decoded from<br/>the artifact project's `default_versions_json` output. Selects which<br/>plugin\_arns / plugin\_revisions entry default\_plugin\_arns /<br/>default\_plugin\_revisions expose for a consumer that always wants "the<br/>current one" rather than naming a version. | `map(string)` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for each custom plugin name; the full name is hyphen-joined as <name\_prefix>-<plugin-key>. Defaults to "debezium". | `string` | `"debezium"` | no |
| <a name="input_plugins"></a> [plugins](#input\_plugins) | Custom plugins to register, keyed by full plugin identity<br/>"<flavour>-<version>" (e.g. "mariadb-2.7.4.Final"). Each entry gives the<br/>artifact's S3 file key and, when the bucket is versioned, its object<br/>version. Decoded from the artifact project's single `plugins_json` output.<br/>A version bump ADDS a new key (old and new plugins coexist); remove a key<br/>only after no connector references it — see README.md. | <pre>map(object({<br/>    file_key       = string<br/>    object_version = optional(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | n/a | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_default_plugin_arns"></a> [default\_plugin\_arns](#output\_default\_plugin\_arns) | Custom plugin ARN of the default version, keyed by flavour, for a consumer that wants "the current one" rather than naming a version. |
| <a name="output_default_plugin_revisions"></a> [default\_plugin\_revisions](#output\_default\_plugin\_revisions) | Latest custom plugin revision of the default version, keyed by flavour. |
| <a name="output_plugin_arns"></a> [plugin\_arns](#output\_plugin\_arns) | Custom plugin ARNs, keyed by "<flavour>-<version>". |
| <a name="output_plugin_revisions"></a> [plugin\_revisions](#output\_plugin\_revisions) | Latest custom plugin revision, keyed by "<flavour>-<version>", for connectors that pin a revision. |
<!-- END_TF_DOCS -->
