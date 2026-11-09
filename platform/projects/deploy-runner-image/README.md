# deploy-runner-image

Builds the container image that CodeBuild runs every step on. The image holds
the tools, an offline Terraform provider mirror, and baked Python envs. A
runner with no internet access can use it.

## Use the image

Run this project in the operations pipeline, after `ecr`. It runs on the stock
CodeBuild image. Then set the image in each pipeline that uses it:

```yaml
codebuild:
  image_repo: "<OPERATIONS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/deploy-runner-image"
```

The autopilot adds the tag `:<propeller_version>`.

## Manifest

`image.yaml` lists the image content. It has one section per kind. Each
section is a map of components, keyed by name. The key is the component name
everywhere.

```yaml
packages:
  jq: { required: true }
binaries:
  terraform:
    version: "1.15.8"
    check: terraform version
    url: https://releases.hashicorp.com/terraform/{version}/terraform_{version}_linux_{arch}.zip
    checksum_url: https://releases.hashicorp.com/terraform/{version}/terraform_{version}_SHA256SUMS
    extract: terraform
```

Fields for all components:

- `enabled`: default `true`. Set `false` to remove the component.
- `required`: default `false`. Only `image.yaml` sets it. You cannot disable a
  required component.

Sections, in install order:

- `packages`: dnf packages. The key is the package name. Use `{}` for no
  fields.
- `binaries`: files in `/usr/local/bin/<key>`. Set an exact `version`, a `url`
  and a `checksum_url`. Set `extract` for archives. `{version}` and `{arch}`
  expand in these fields. `arch` maps `amd64` and `arm64` to upstream names.
  `check` is an optional command. Before the push, the build checks that each
  binary is an executable for the target architecture and runs its `check`.
- `terraform_providers`: providers in the offline mirror. Set `source`
  (`<namespace>/<type>` on the public registry) and a `version` constraint,
  for example `~> 6.49.0`.
- `python_envs`: venvs in `/opt/propeller/python/<key>`. `path` is a directory
  with `pyproject.toml`, `uv.lock` and `.python-version`. Its name must be the
  key. uv installs the dependencies only, never the env itself.
- `scripts`: executable files at `path`. Scripts run last, as root, with
  network access. They must verify what they download.

A `path` is relative to the file that declares it.

## Overrides

Put `image.overrides.yaml` in the overlay of this project. It has the same
shape as `image.yaml` and merges by section and key. A new key adds a
component. An existing key gets the new field values. A field set to `null` is
removed. You can only disable a component that exists.

```yaml
version: "1"
binaries:
  kubectl:
    enabled: false
  terraform:
    version: "1.15.9"
python_envs:
  my-tools:
    path: python/my-tools
```

`just show` prints the merged manifest. `just plan` validates it, lists the
components, and shows the changes since the last apply.

## Built manifest

The build adds a `resolved` object to what it installs: the base image digest,
package versions, the URL and sha256 of each binary, provider versions, and the
Python version of each env. The image has this file at
`/etc/propeller/image.json`.

`apply` exports the file and stores it in the state bucket, next to the
Terraform state. `plan` compares the new manifest with it, without `resolved`.
`apply` compares the built manifests, so it also shows a new base image,
package updates, and provider versions that changed under a constraint.

## Python envs

A project runs Python with the `py-run` recipe:

```just
import "../../../shared/recipes/python.just"

apply: (py-run "../../shared/python/my-env" "python" "main.py")
```

On this image, `py-run` uses the baked venv offline. First it checks that the
venv matches the `uv.lock` in the bundle. If the lock is different, it stops:
rebuild the image. On an image without the env, uv builds the env from the
bundle. This needs network access.

If projects need different versions of a package, give each its own env.

A consumer env is in two places: in the overlay of this project, and in each
project that uses it. Keep the two copies equal. `py-run` stops if they
differ.

## Test

`just test-image` (repository root) builds the image with
`tests/image.overrides.yaml` and checks it, also with no network.
