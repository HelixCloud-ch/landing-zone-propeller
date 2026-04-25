# Development tasks for the propeller framework.

# Install engine dependencies
setup:
    uv sync --project engine

# Resolve the pipeline (smoke test)
resolve:
    mkdir -p dist
    uv run --project engine propeller-resolve \
        --base propeller.yaml \
        --output dist/pipeline.lock.yaml \
        --propeller-dir .

# Validate the resolved pipeline
validate:
    uv run --project engine propeller-validate \
        --pipeline dist/pipeline.lock.yaml \
        --no-check-sources

# Check terraform formatting
fmt-check:
    terraform fmt -check -recursive projects/ autopilot/terraform/

# Format terraform files
fmt:
    terraform fmt -recursive projects/ autopilot/terraform/

# Smoke test: resolve + validate
test: resolve validate
    @echo "All checks passed."

# Clean build artifacts
clean:
    rm -rf dist engine/.venv
