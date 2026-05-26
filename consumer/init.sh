#!/usr/bin/env bash
# Bootstrap a new propeller consumer repository.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/HelixCloud-ch/landing-zone-propeller/main/consumer/init.sh | bash
#   curl -fsSL ... | bash -s -- --version v1.0.0
set -euo pipefail

REPO="HelixCloud-ch/landing-zone-propeller"
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "Fetching latest release..."
    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases?per_page=1" | grep -m1 '"tag_name"' | cut -d'"' -f4)
    if [[ -z "$VERSION" ]]; then
        echo "Error: could not determine latest version." >&2
        exit 1
    fi
fi

echo "Initializing propeller consumer (${VERSION})..."

# Download framework
rm -rf .propeller
mkdir -p .propeller
curl -fsSL "https://github.com/${REPO}/releases/download/${VERSION}/propeller-${VERSION}.zip" -o /tmp/propeller-init.zip
unzip -qo /tmp/propeller-init.zip -d .propeller
rm -f /tmp/propeller-init.zip

# Copy root templates
cp -n .propeller/consumer/init/.gitignore .gitignore 2>/dev/null || true
cp -n .propeller/consumer/init/justfile justfile 2>/dev/null || true

# Create landing-zone directory with overrides template
mkdir -p landing-zone/projects
cp -n .propeller/consumer/init/propeller.overrides.yaml landing-zone/propeller.overrides.yaml 2>/dev/null || true

# Pin the downloaded version
if grep -q "PROPELLER_VERSION_PLACEHOLDER" landing-zone/propeller.overrides.yaml 2>/dev/null; then
    sed -i.bak "s/PROPELLER_VERSION_PLACEHOLDER/${VERSION}/" landing-zone/propeller.overrides.yaml
    rm -f landing-zone/propeller.overrides.yaml.bak
fi

echo ""
echo "Done! Next steps:"
echo "  1. Edit landing-zone/propeller.overrides.yaml"
echo "  2. Run: just build"
echo ""
