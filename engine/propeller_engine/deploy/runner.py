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


def log(msg: str) -> None:
    click.echo(f"[propeller] {msg}", err=True)


def load_project_yaml(project_dir: Path) -> dict:
    path = project_dir / "project.yaml"
    if not path.exists():
        raise click.ClickException(f"project.yaml not found in {project_dir}")
    return yaml.safe_load(path.read_text())


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


def run_cmd(cmd: list[str], cwd: Path | None = None) -> int:
    log(f"Running: {' '.join(cmd)}")
    return subprocess.run(cmd, cwd=cwd).returncode


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
        config: str | None,
    ):
        self.project = project
        self.project_dir = project_dir
        self.inputs = inputs
        self.config = config

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
    project: dict, project_dir: Path, inputs: dict[str, str], config: str | None
) -> DeployRunner:
    deploy_type = project.get("deploy", {}).get("type", "")

    if deploy_type == "terraform":
        from .terraform import TerraformRunner

        return TerraformRunner(project, project_dir, inputs, config)
    elif deploy_type == "cloudformation":
        from .cloudformation import CloudFormationRunner

        return CloudFormationRunner(project, project_dir, inputs, config)
    elif deploy_type == "script":
        from .script import ScriptRunner

        return ScriptRunner(project, project_dir, inputs, config)
    else:
        raise click.ClickException(f"Unknown deploy type: {deploy_type}")
