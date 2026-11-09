# shared/recipes/python.just
#
# Run a command inside a python env. Import from project justfiles:
#   import "../../../shared/recipes/python.just"
# and call it as a dependency:
#   apply: (py-run "../../shared/python/<env>" "python" "main.py")
#
# ENV is the env directory in the bundle (pyproject.toml, uv.lock,
# .python-version). Its
# directory name is the env key, the same key as in the image manifest.
#
# On the deploy-runner image the env is baked at /opt/propeller/python/<key>.
# py-run checks that the baked venv matches the bundle's uv.lock, then runs
# offline. Without a baked env (stock CodeBuild image, laptop) uv builds the
# env from the bundle, which needs network access.

[private]
[positional-arguments]
py-run env +cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    env_dir="$1"
    shift
    key="$(basename "$env_dir")"
    baked="/opt/propeller/python/${key}/.venv"

    uv_args=(--quiet --project "$env_dir" --frozen --no-dev)
    # Envs are not packages: sync installs the dependencies, never the env
    # itself. `uv run` always runs with --no-sync, after an explicit sync.
    sync_args=("${uv_args[@]}" --no-install-project)

    if [[ ! -d "$baked" ]]; then
      if [[ -f /etc/propeller/image.json ]]; then
        echo "py-run: env '$key' is not in this image; building it from the bundle (needs network access)." >&2
        echo "py-run: to run offline, add '$key' to python_envs in the image manifest." >&2
      fi
      uv sync "${sync_args[@]}"
      exec uv run "${uv_args[@]}" --no-sync -- "$@"
    fi

    export UV_PROJECT_ENVIRONMENT="$baked"
    log="$(mktemp)"
    if ! uv sync "${sync_args[@]}" --offline --check 2>"$log"; then
      cat "$log" >&2
      echo "py-run: the image's env '$key' does not match $env_dir/uv.lock." >&2
      echo "py-run: rebuild deploy-runner-image so the image carries this lock." >&2
      exit 1
    fi
    rm -f "$log"
    exec uv run "${uv_args[@]}" --offline --no-sync -- "$@"
