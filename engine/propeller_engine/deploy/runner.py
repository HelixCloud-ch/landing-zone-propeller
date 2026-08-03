"""Base deploy runner and dispatch logic."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

import click
import yaml

ENV_VAR_RE = re.compile(r"\$\{(\w+)\}")
INPUT_PREFIX = "PROPELLER_INPUT_"
OUTPUTS_FILE = ".propeller-outputs.json"
PROPELLER_TAGS_ENV = "PROPELLER_FRAMEWORK_TAGS_JSON"
CONSUMER_TAGS_ENV = "PROPELLER_CONSUMER_TAGS_JSON"


def log(msg: str) -> None:
    click.echo(f"[propeller] {msg}", err=True)


def load_project_yaml(project_dir: Path) -> dict:
    path = project_dir / "project.yaml"
    if not path.exists():
        raise click.ClickException(f"project.yaml not found in {project_dir}")
    return yaml.safe_load(path.read_text())


def resolve_project_dir(pipeline_path: Path, project: str) -> Path:
    """Return the project's directory, looked up by name in a resolved pipeline.

    The resolved lock stores each step's bundle-relative ``source``. Paths are
    resolved relative to the lock file's directory (the bundle root).
    """
    data = yaml.safe_load(pipeline_path.read_text())
    for stage in data.get("stages", []):
        for step in stage.get("steps", []):
            if step.get("project") == project:
                source = step.get("source")
                if not source:
                    raise click.ClickException(
                        f"Project '{project}' has no source in {pipeline_path}"
                    )
                return (pipeline_path.parent / source).resolve()
    raise click.ClickException(f"Project '{project}' not found in {pipeline_path}")


def substitute_env(value: str) -> str:
    def replacer(match: re.Match) -> str:
        var_name = match.group(1)
        val = os.environ.get(var_name)
        if val is None:
            raise click.ClickException(
                f"Environment variable ${{{var_name}}} is not set"
            )
        return val

    return ENV_VAR_RE.sub(replacer, value)


def collect_inputs() -> dict[str, str]:
    return {
        key[len(INPUT_PREFIX) :]: value
        for key, value in os.environ.items()
        if key.startswith(INPUT_PREFIX)
    }


def collect_tags() -> tuple[dict[str, str], dict[str, str]]:
    """Return (propeller_tags, consumer_tags) parsed from the environment."""

    def _parse(name: str) -> dict[str, str]:
        raw = os.environ.get(name, "").strip()
        if not raw:
            return {}
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise click.ClickException(f"{name} is not valid JSON: {exc}") from exc
        if not isinstance(data, dict):
            raise click.ClickException(f"{name} must decode to a JSON object")
        return {str(k): str(v) for k, v in data.items()}

    return _parse(PROPELLER_TAGS_ENV), _parse(CONSUMER_TAGS_ENV)


def run_cmd(
    cmd: list[str], cwd: Path | None = None, env: dict[str, str] | None = None
) -> int:
    log(f"Running: {' '.join(cmd)}")
    return subprocess.run(cmd, cwd=cwd, env=env).returncode


def write_outputs_file(outputs: dict, project_dir: Path) -> None:
    out_path = project_dir / OUTPUTS_FILE
    out_path.write_text(json.dumps(outputs, indent=2))
    log(f"Outputs written to {out_path}")


class DeployRunner:
    """Base class for deploy runners."""

    def __init__(
        self,
        project: dict,
        project_dir: Path,
        inputs: dict[str, str],
        propeller_tags: dict[str, str] | None = None,
        consumer_tags: dict[str, str] | None = None,
    ):
        self.project = project
        self.project_dir = project_dir
        self.inputs = inputs
        self.propeller_tags = propeller_tags or {}
        self.consumer_tags = consumer_tags or {}

    def init(self) -> int:
        raise NotImplementedError

    def plan(self) -> int:
        raise NotImplementedError

    def apply(self) -> int:
        raise NotImplementedError

    def destroy(self) -> int:
        raise NotImplementedError

    def outputs(self) -> int:
        raise NotImplementedError


def get_runner(
    project: dict,
    project_dir: Path,
    inputs: dict[str, str],
    propeller_tags: dict[str, str] | None = None,
    consumer_tags: dict[str, str] | None = None,
) -> DeployRunner:
    deploy_type = project.get("deploy", {}).get("type", "")

    if deploy_type == "terraform":
        from .terraform import TerraformRunner

        return TerraformRunner(
            project, project_dir, inputs, propeller_tags, consumer_tags
        )
    elif deploy_type == "cloudformation":
        from .cloudformation import CloudFormationRunner

        return CloudFormationRunner(
            project, project_dir, inputs, propeller_tags, consumer_tags
        )
    elif deploy_type == "script":
        from .script import ScriptRunner

        return ScriptRunner(project, project_dir, inputs, propeller_tags, consumer_tags)
    elif deploy_type == "just":
        from .script import ScriptRunner

        return ScriptRunner(project, project_dir, inputs, propeller_tags, consumer_tags)
    else:
        raise click.ClickException(f"Unknown deploy type: {deploy_type}")
