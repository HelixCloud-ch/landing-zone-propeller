#!/usr/bin/env bash
#
# Builds the deploy-runner image from image.yaml + tests/image.overrides.yaml
# and verifies it: tool versions match the manifest, the image describes
# itself, terraform init and py-run work with no network, and py-run refuses
# an env whose lock differs from the image.
#
# Usage: ./test.sh   (or: just test-image)
set -euo pipefail
cd "$(dirname "$0")/.."
repo="$(cd ../../.. && pwd)"
image="deploy-runner-image:test"

# Build for the host platform (native, fast). Production builds target amd64 via
# the justfile; the test validates the Dockerfile logic and mirror on either arch.
arch=$(uname -m)
case "$arch" in x86_64) arch=amd64 ;; aarch64 | arm64) arch=arm64 ;; esac

if [[ -t 1 ]]; then
  _sub=$'\033[1;34m' _ok=$'\033[1;97;42m' _fail=$'\033[1;97;41m' _reset=$'\033[0m'
else
  _sub="" _ok="" _fail="" _reset=""
fi
section() { printf '\n%s[test] %s%s\n' "$_sub" "$1" "$_reset"; }

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
run() { docker run --rm "$image" "$@"; }

# ── Render + build ──────────────────────────────────────────────────────────
section "render manifest (image.yaml + tests/image.overrides.yaml)"
uv run --quiet --project renderer --frozen --no-dev python renderer/render.py \
  --overrides tests/image.overrides.yaml stage --out .build
manifest=.build/image.json
version_of() { jq -r --arg k "$1" '.binaries[$k].version' "$manifest"; }

echo "${_sub}[build] platform: linux/$arch${_reset}"
docker rmi "$image" >/dev/null 2>&1 || true
read -r base_ref base_digest < <(just _base-ref)
build_args=(--provenance=false
  --build-arg BASE_IMAGE="$base_ref" --build-arg BASE_DIGEST="$base_digest"
  --build-arg PROPELLER_VERSION=test)
docker buildx build "${build_args[@]}" --target final --load -t "$image" .

section "image size"
docker image ls "$image"

# ── Tools ───────────────────────────────────────────────────────────────────
section "baked tool versions (from the manifest)"
check terraform "$(version_of terraform)" "$(run terraform version 2>/dev/null | head -1 || true)"
check just      "$(version_of just)"      "$(run just --version 2>/dev/null || true)"
check uv        "$(version_of uv)"        "$(run uv --version 2>/dev/null || true)"
check kubectl   "$(version_of kubectl)"   "$(run kubectl version --client 2>/dev/null | head -1 || true)"
check helm      "$(version_of helm)"      "$(run helm version --short 2>/dev/null || true)"

section "recipe runtime deps"
# The shared recipes shell out to these; a base swap dropping one would only
# surface at deploy time, so guard them here.
present() {
  local name="$1"; shift
  if run "$@" >/dev/null 2>&1; then echo "ok:   $name present"; else echo "FAIL: $name missing"; fail=1; fi
}
present aws     aws --version
present jq      jq --version
present python3 python3 --version
present git     git --version
present boto3   python3 -c "import boto3"
check python3-default "3.14" "$(run python3 --version 2>&1 || true)"

# ── Self-description ────────────────────────────────────────────────────────
section "image manifest (/etc/propeller/image.json)"
baked="$(run cat /etc/propeller/image.json)"
check build.propeller_version test "$(jq -r .build.propeller_version <<<"$baked")"
check base.resolved.digest "$base_digest" "$(jq -r '.base.resolved.digest // ""' <<<"$baked")"
# Every enabled package, binary, provider and env records what the build got.
unresolved="$(jq -r '["packages", "binaries", "terraform_providers", "python_envs"][] as $s
  | .[$s] | to_entries[] | select(.value.enabled and (.value.resolved // {} | length) == 0)
  | "\($s).\(.key)"' <<<"$baked")"
if [[ -z "$unresolved" ]]; then
  echo "ok:   every package, binary, provider and env has a resolved object"
  jq -r '.terraform_providers | to_entries[]
    | "      \(.value.source) \(.value.version) -> \(.value.resolved.version)"' <<<"$baked"
  jq -r '"      jq package -> \(.packages.jq.resolved.version)",
    "      uv binary sha256 -> \(.binaries.uv.resolved.sha256)",
    "      python-smoke env python -> \(.python_envs["python-smoke"].resolved.python)"' <<<"$baked"
else
  echo "FAIL: no resolved object for: $unresolved"; fail=1
fi
if jq -e '[.binaries[] | has("artifacts")] | any' <<<"$baked" >/dev/null; then
  echo "FAIL: built manifest still lists per-arch artifacts"; fail=1
else
  echo "ok:   built manifest has no per-arch artifacts"
fi
check script-ran "zz-test-marker ran" "$(run cat /etc/propeller/test-marker 2>/dev/null || true)"

section "manifest export (--target manifest, as apply does)"
export_dir="$(mktemp -d)"
docker buildx build "${build_args[@]}" --target manifest --output "type=local,dest=$export_dir" . >/dev/null 2>&1
if [[ "$(cat "$export_dir/image.json" 2>/dev/null)" == "$baked" ]]; then
  echo "ok:   exported manifest equals /etc/propeller/image.json"
else
  echo "FAIL: exported manifest differs from /etc/propeller/image.json"; fail=1
fi
rm -rf "$export_dir"

# ── Terraform ───────────────────────────────────────────────────────────────
section "provider mirror constraints"
result_file=$(mktemp)
docker run --rm \
  -v "$repo:/repo:ro" \
  -v "$(pwd)/tests/check_providers.py:/check_providers.py:ro" \
  "$image" python3 /check_providers.py | tee "$result_file"
if grep -q "FAIL:" "$result_file"; then
  echo "FAIL: a provider constraint is not satisfied by the mirror (update image.yaml)"
  fail=1
fi
rm -f "$result_file"

section "offline init (one provider, proves the mirror wiring)"
read -r test_src test_ver < <(jq -r '[.terraform_providers[] | select(.enabled)][0]
  | "\(.source) \(.version)"' "$manifest")
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

# ── Python ──────────────────────────────────────────────────────────────────
# The container gets a bundle-shaped copy of the files python-smoke needs, so
# py-run sees the same relative paths it sees in CodeBuild.
bundle_cmd='
  set -euo pipefail
  mkdir -p /tmp/bundle/platform/projects /tmp/bundle/platform/shared /tmp/bundle/shared
  cp -r /repo/platform/projects/python-smoke /tmp/bundle/platform/projects/
  cp -r /repo/platform/shared/python /tmp/bundle/platform/shared/
  cp -r /repo/shared/recipes /tmp/bundle/shared/
  cd /tmp/bundle/platform/projects/python-smoke
'

section "py-run offline (python-smoke on the baked env)"
if out="$(docker run --rm --network none -v "$repo:/repo:ro" "$image" bash -c "
  $bundle_cmd
  just apply >&2
  cat .propeller-outputs.json
")"; then
  want_pyyaml="$(sed -n 's/.*"pyyaml==\(.*\)".*/\1/p' "$repo/platform/shared/python/python-smoke/pyproject.toml")"
  check python_version "3.14" "$(jq -r .python_version <<<"$out")"
  check pyyaml_version "$want_pyyaml" "$(jq -r .pyyaml_version <<<"$out")"
  check pyyaml_libyaml "true" "$(jq -r .pyyaml_libyaml <<<"$out")"
  check interpreter "/opt/propeller/python/python-smoke/.venv" "$(jq -r .interpreter <<<"$out")"
else
  echo "FAIL: python-smoke apply failed offline"
  fail=1
fi

section "py-run refuses a lock that differs from the image"
if out="$(docker run --rm --network none -v "$repo:/repo:ro" "$image" bash -c "
  $bundle_cmd
  sed -i 's/^version = \"6\.0\.3\"/version = \"6.0.2\"/' ../../shared/python/python-smoke/uv.lock
  just apply
" 2>&1)"; then
  echo "FAIL: py-run ran with a lock that differs from the image"
  fail=1
else
  check drift-message "does not match" "$(grep 'py-run:' <<<"$out" | head -1)"
fi

# ── Build steps on edge cases ───────────────────────────────────────────────
# Run single steps inside the image against a hand-written manifest.
steps_mount=(-v "$(pwd)/steps:/steps:ro")

section "python step: a manifest with no envs"
if docker run --rm --network none "${steps_mount[@]}" "$image" bash -c '
  echo "{\"python_envs\": {}}" > /tmp/m.json && mkdir /tmp/src && bash /steps/python.sh /tmp/m.json /tmp/src'; then
  echo "ok:   python.sh succeeds with no envs"
else
  echo "FAIL: python.sh fails with no envs"; fail=1
fi

section "python step: an env that is a uv package"
if docker run --rm "${steps_mount[@]}" "$image" bash -c '
  set -euo pipefail
  mkdir -p /tmp/src/pkgenv && cd /tmp/src/pkgenv
  printf "[project]\nname = \"pkgenv\"\nversion = \"0\"\nrequires-python = \">=3.14\"\ndependencies = []\n\n[build-system]\nrequires = [\"hatchling\"]\nbuild-backend = \"hatchling.build\"\n" > pyproject.toml
  echo 3.14 > .python-version
  uv lock --quiet
  echo "{\"python_envs\": {\"pkgenv\": {\"enabled\": true}}}" > /tmp/m.json
  bash /steps/python.sh /tmp/m.json /tmp/src >/dev/null' 2>&1; then
  echo "ok:   python.sh builds a package env (dependencies only)"
else
  echo "FAIL: python.sh cannot build a package env"; fail=1
fi

section "finalize step: rejects a binary that is not an ELF executable"
if out="$(docker run --rm --network none "${steps_mount[@]}" "$image" bash -c '
  printf "#!/bin/sh\necho hi\n" > /usr/local/bin/fake && chmod +x /usr/local/bin/fake
  echo "{\"binaries\": {\"fake\": {\"enabled\": true}}}" > /tmp/m.json
  echo "{}" > /tmp/fetched.json
  bash /steps/finalize.sh /tmp/m.json test '"$arch"' "" /tmp/fetched.json' 2>&1)"; then
  echo "FAIL: finalize.sh accepted a non-ELF binary"; fail=1
else
  check finalize-message "not an ELF executable" "$out"
fi

if [[ "$fail" -ne 0 ]]; then
  printf '\n%s  %-46s  %s\n' "$_fail" "FAIL" "$_reset"
  exit 1
fi
printf '\n%s  %-46s  %s\n' "$_ok" "PASS" "$_reset"
