#!/usr/bin/env bash
# Mirror the enabled terraform providers into /opt/tf-providers and
# point terraform at the mirror only (no `direct {}`: init never hits the
# network). Records the version each constraint resolved to as
# `resolved.version` in the manifest.
# Usage: providers.sh MANIFEST ARCH
set -euo pipefail
manifest="$1" arch="$2"
. "$(dirname "$0")/lib.sh"

mirror=/opt/tf-providers
mkdir -p "$mirror"

keys="$(enabled_keys "$manifest" terraform_providers)"
for key in $keys; do
  source="$(field "$manifest" terraform_providers "$key" source)"
  version="$(field "$manifest" terraform_providers "$key" version)"
  config="$(mktemp -d)"
  cat > "$config/main.tf" <<HCL
terraform {
  required_providers {
    ${source##*/} = { source = "$source", version = "$version" }
  }
}
HCL
  echo "terraform-provider $key: $source $version"
  if ! log="$(cd "$config" && terraform providers mirror -platform="linux_$arch" "$mirror" 2>&1)"; then
    echo "$log" >&2
    exit 1
  fi
  resolved="$(sed -n 's/.*Selected v\([^ ]*\) .*/\1/p' <<<"$log" | head -1)"
  if [[ -z "$resolved" ]]; then
    echo "$log" >&2
    echo "terraform-provider $key: could not read the selected version" >&2
    exit 1
  fi
  echo "  resolved: $resolved"
  set_resolved "$manifest" terraform_providers "$key" version "$resolved"
  rm -rf "$config"
done

cat > /etc/terraformrc <<HCL
provider_installation {
  filesystem_mirror {
    path    = "$mirror"
    include = ["*/*"]
  }
}
HCL
