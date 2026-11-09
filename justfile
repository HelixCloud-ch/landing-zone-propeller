# Development tasks for the propeller framework.

# Install engine dependencies
setup:
    uv sync --project engine

_hdr := '\033[1;97;44m'   # bold white on blue
_ok := '\033[1;97;42m'    # bold white on green
_reset := '\033[0m'

# Print a section header banner (used as a dependency by the test recipes).
[private]
section msg:
    @printf '\n{{ _hdr }}  %-60s  {{ _reset }}\n\n' '{{ msg }}'

# Resolve the pipeline (smoke test)
resolve: (section "resolve pipeline")
    @mkdir -p dist
    @uv run --project engine propeller-resolve \
        --base landing-zone/propeller.yaml \
        --output dist/pipeline.lock.yaml \
        --propeller-dir landing-zone

# Validate the resolved pipeline
validate: (section "validate pipeline")
    @uv run --project engine propeller-validate \
        --pipeline dist/pipeline.lock.yaml \
        --no-check-sources

# Check terraform formatting
fmt-check:
    terraform fmt -check -recursive landing-zone/projects/ platform/ autopilot/terraform/

# Format terraform files
fmt:
    terraform fmt -recursive landing-zone/projects/ platform/ autopilot/terraform/

# ── Tests ─────────────────────────────────────────────────────────────────────
# `just test` runs everything; run a sub-recipe to test one piece.

# Engine unit tests (pytest)
test-engine: (section "engine: pytest")
    @cd engine && uv run pytest -q --tb=short

# Autopilot unit tests + typecheck. Uses an installed pnpm if present, else runs
# the version pinned in package.json's packageManager via corepack (bundled with
# Node, no global install). CI=1 keeps the one-time reinstall non-interactive.
test-autopilot: (section "autopilot: vitest + tsc")
    #!/usr/bin/env bash
    set -euo pipefail
    cd autopilot
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0 CI=1
    if command -v pnpm >/dev/null; then pm=(pnpm); else pm=(corepack pnpm); fi
    "${pm[@]}" install --frozen-lockfile
    "${pm[@]}" test
    "${pm[@]}" run typecheck

# Shell recipes: value flow (aggregator, _propeller-vars) and consumer `wait`
test-recipes: (section "recipes: value flow + wait")
    @./shared/recipes/tests/value-flow.sh
    @./consumer/tests/wait.sh

# Build and verify the deploy-runner image. Heavy (docker + buildx + egress,
# ~minutes), so it's not part of `test`; run it explicitly or via `test-all`.
test-image: (section "deploy-runner image: build + offline verify")
    @./platform/projects/deploy-runner-image/tests/test.sh

# Show the deploy-runner image's space breakdown (build it first: just test-image)
image-size:
    #!/usr/bin/env bash
    set -euo pipefail
    img=deploy-runner-image:test
    docker image inspect "$img" >/dev/null 2>&1 || { echo "image not built — run: just test-image"; exit 1; }
    echo "== image =="
    docker image ls "$img"
    echo
    echo "== filesystem =="
    docker run --rm --entrypoint sh "$img" -c 'du -xsh /* 2>/dev/null | sort -rh | head -8'
    echo
    echo "== providers =="
    docker run --rm --entrypoint sh "$img" -c 'du -sh /opt/tf-providers/*/*/* 2>/dev/null | sort -rh'
    echo
    echo "== tools =="
    docker run --rm --entrypoint sh "$img" -c 'du -sh /usr/local/aws-cli /usr/local/bin/terraform /usr/local/bin/helm /usr/local/bin/kubectl /usr/local/bin/just 2>/dev/null | sort -rh'

# Check tool version sync between versions.env and the buildspec in constants.ts
check-versions-sync:
    @./platform/projects/deploy-runner-image/tests/check_versions_sync.sh

# The CDC tests run in their own venv on a uv-managed Python, both in dist/
# (gitignored, removed by `just clean`). A Python installed on the machine,
# for example an old 3.14 pre-release, is never used.
_cdc_uv := "env UV_PYTHON_PREFERENCE=only-managed UV_PYTHON_INSTALL_DIR=" + justfile_directory() + "/dist/test-python UV_PROJECT_ENVIRONMENT=" + justfile_directory() + "/dist/cdc-venv uv run --quiet --project platform/shared/python/cdc"

# CDC Python projects (pytest in the shared cdc env). One run per project:
# each has its own prepare/topics module.
test-cdc: (section "cdc: pytest")
    #!/usr/bin/env bash
    set -euo pipefail
    for p in cdc-prepare-mariadb cdc-prepare-oracle cdc-topics; do
      {{ _cdc_uv }} pytest -q -p no:cacheprovider "platform/projects/$p"
    done

_cdc_compose := "docker compose -f platform/shared/python/cdc/tests/compose.yaml"

# Start MariaDB, Oracle and Kafka for the CDC integration tests. Oracle takes
# about a minute on the first start. They keep running until `just cdc-down`.
cdc-up:
    {{ _cdc_compose }} up -d --wait

# Stop the CDC integration services and delete their data
cdc-down:
    {{ _cdc_compose }} down -v

# CDC scripts against real MariaDB, Oracle and Kafka (needs Docker). Starts the
# services, runs the tests, stops the services.
test-cdc-integration: (section "cdc: integration") cdc-up
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'just cdc-down' EXIT
    {{ _cdc_uv }} pytest -q -p no:cacheprovider platform/shared/python/cdc/tests

# Fast tests: pipeline resolve/validate + engine + autopilot (no docker)
test: resolve validate test-engine test-autopilot test-recipes test-image-manifest check-versions-sync test-cdc
    @printf '\n{{ _ok }}  %-60s  {{ _reset }}\n' 'PASS: all checks passed'

# Everything, including the heavy image build/verify
test-all: test test-image
    @printf '\n{{ _ok }}  %-60s  {{ _reset }}\n' 'PASS: all tests passed'

# Clean build artifacts
clean:
    rm -rf dist engine/.venv autopilot/dist autopilot/node_modules
