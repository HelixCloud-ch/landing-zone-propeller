"""CLI: propeller-deploy"""

from __future__ import annotations

import sys
from pathlib import Path

import click

from ..deploy.runner import collect_inputs, get_runner, load_project_yaml, log


@click.group()
@click.option(
    "--project-dir",
    default=".",
    type=click.Path(exists=True),
    help="Project directory containing project.yaml",
)
@click.option(
    "--config",
    default=None,
    type=click.Path(),
    help="Path to config file (e.g., .tfvars for terraform)",
)
@click.pass_context
def main(ctx: click.Context, project_dir: str, config: str | None) -> None:
    """Deploy a propeller project based on its project.yaml."""
    ctx.ensure_object(dict)
    project_dir_path = Path(project_dir).resolve()
    project = load_project_yaml(project_dir_path)
    inputs = collect_inputs()

    log(f"Project: {project['name']}")
    for var_name, value in inputs.items():
        log(f"Input: {var_name} = {value}")

    ctx.obj["runner"] = get_runner(project, project_dir_path, inputs, config)


@main.command()
@click.pass_context
def init(ctx: click.Context) -> None:
    """Initialize the project."""
    sys.exit(ctx.obj["runner"].init())


@main.command()
@click.pass_context
def plan(ctx: click.Context) -> None:
    """Plan the deployment."""
    sys.exit(ctx.obj["runner"].plan())


@main.command()
@click.pass_context
def apply(ctx: click.Context) -> None:
    """Apply the deployment and export outputs."""
    sys.exit(ctx.obj["runner"].apply())


@main.command()
@click.pass_context
def destroy(ctx: click.Context) -> None:
    """Destroy the deployed resources."""
    sys.exit(ctx.obj["runner"].destroy())


@main.command()
@click.pass_context
def outputs(ctx: click.Context) -> None:
    """Print current outputs (debug helper)."""
    sys.exit(ctx.obj["runner"].outputs())
