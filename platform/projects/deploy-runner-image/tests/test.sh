#!/usr/bin/env bash
#
# Builds the deploy-runner image and verifies it: baked tool versions match
# versions.env, the recipe runtime deps are present, and terraform init resolves
# offline from the baked provider mirror.
#
# Usage: ./test.sh   (or: just test-image)
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; . ./versions.env; set +a

image="deploy-runner-image:test"

# Build for the host platform (native, fast). Production builds target amd64 via
# the justfile; the test validates the Dockerfile logic and mirror on either arch.
arch=$(uname -m)
case "$arch" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; esac
# Colors: disable if not a terminal (piped, CI without color support).
if [[ -t 1 ]]; then
  _sub=$'\033[1;34m'     # bold blue text (sub-sections)
  _ok=$'\033[1;97;42m'   # bold white on green
  _fail=$'\033[1;97;41m' # bold white on red
  _reset=$'\033[0m'
else
  _sub="" _ok="" _fail="" _reset=""
fi

section() { printf '\n%s[test] %s%s\n' "$_sub" "$1" "$_reset"; }

echo "${_sub}[build] platform: linux/$arch${_reset}"
docker rmi "$image" >/dev/null 2>&1 || true
docker buildx build --provenance=false \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg TERRAFORM_VERSION="$TERRAFORM_VERSION" \
  --build-arg JUST_VERSION="$JUST_VERSION" \
  --build-arg KUBECTL_VERSION="$KUBECTL_VERSION" \
  --build-arg HELM_VERSION="$HELM_VERSION" \
  --load -t "$image" .

run() { docker run --rm "$image" "$@"; }

section "image size"
docker image ls "$image"

fail=0
check() {
  local name="$1" want="$2" got="$3"
  if [[ "$got" == *"$want"* ]]; then
    echo "ok:   $name -> $got"
  else
    echo "FAIL: $name -> '$got' (expected to contain '$want')"
    fail=1
  fi
}

section "baked tool versions"
check terraform "$TERRAFORM_VERSION" "$(run terraform version 2>/dev/null | head -1 || true)"
check just      "$JUST_VERSION"      "$(run just --version 2>/dev/null || true)"
check kubectl   "$KUBECTL_VERSION"   "$(run kubectl version --client 2>/dev/null | head -1 || true)"
check helm      "$HELM_VERSION"      "$(run helm version --short 2>/dev/null || true)"

section "recipe runtime deps"
# The shared terraform recipe shells out to these; a base swap dropping one
# would only surface at deploy time, so guard them here.
present() {
  local name="$1"; shift
  if run "$@" >/dev/null 2>&1; then
    echo "ok:   $name present"
  else
    echo "FAIL: $name missing or not runnable"
    fail=1
  fi
}
present aws     aws --version
present jq      jq --version
present python3 python3 --version
present git     git --version

section "provider mirror contents"
docker run --rm "$image" bash -c "
  for zip in /opt/tf-providers/registry.terraform.io/*/*/*.zip; do
    [ -f \"\$zip\" ] || continue
    echo \"\$zip\" | sed 's|.*/registry.terraform.io/||; s|/terraform-provider-[^_]*_| |; s/_linux.*//; s|/| |'
  done | sort
"

section "provider mirror constraints"
repo="$(cd ../../../ && pwd)"
tests_dir="$(pwd)/tests"
result_file=$(mktemp)
docker run --rm \
  -v "$repo:/repo:ro" \
  -v "$tests_dir/check_providers.py:/check_providers.py:ro" \
  "$image" python3 /check_providers.py | tee "$result_file"
if grep -q "FAIL:" "$result_file"; then
  echo "FAIL: a provider constraint is not satisfied by the mirror (update providers.txt)"
  fail=1
fi
rm -f "$result_file"

section "offline init (single provider, proves the mirror wiring)"
# Use the first provider entry from providers.txt so we don't hardcode a version.
read -r test_src test_ver < <(grep -v '^\s*#' providers.txt | grep -v '^\s*$' | head -1)
if docker run --rm --network none "$image" bash -c "
  d=\$(mktemp -d) && cd \"\$d\"
  cat > main.tf <<TF
terraform {
  required_providers {
    ${test_src##*/} = { source = \"$test_src\", version = \"$test_ver\" }
  }
}
TF
  terraform init -backend=false -input=false >/dev/null 2>&1
"; then
  echo "ok:   terraform init offline ($test_src $test_ver from mirror)"
else
  echo "FAIL: terraform init offline failed (terraformrc or mirror wiring broken)"
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  printf '\n%s  %-46s  %s\n' "$_fail" "FAIL" "$_reset"
  exit 1
fi
printf '\n%s  %-46s  %s\n' "$_ok" "PASS" "$_reset"
