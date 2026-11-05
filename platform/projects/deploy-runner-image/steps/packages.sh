#!/usr/bin/env bash
# Install the enabled packages with dnf and record each installed version.
# Usage: packages.sh MANIFEST
set -euo pipefail
manifest="$1"
. "$(dirname "$0")/lib.sh"

# The build steps read the manifest with jq, so it is installed first.
dnf install -y --setopt=install_weak_deps=False jq

packages="$(enabled_keys "$manifest" packages)"
if [[ -n "$packages" ]]; then
  echo "packages:" $packages
  # shellcheck disable=SC2086 # a word list, see enabled_keys
  dnf install -y --setopt=install_weak_deps=False $packages
fi
dnf clean all
rm -rf /var/cache/dnf

# --whatprovides: the key can be a provided name (awscli is awscli-2).
for key in $packages; do
  version="$(rpm -q --whatprovides "$key" --qf '%{VERSION}-%{RELEASE}\n' | head -1)"
  set_resolved "$manifest" packages "$key" version "$version"
done
