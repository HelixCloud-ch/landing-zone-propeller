"""CLI: propeller-deploy"""

from __future__ import annotations

import sys
from pathlib import Path

import click

from ..deploy.runner import (
    collect_inputs,
    collect_tags,
    get_runner,
    load_project_yaml,
    log,
    resolve_project_dir,
)


@click.group()
@click.option(
    "--project-dir",
    default=None,
    type=click.Path(exists=True),
    help="Project directory containing project.yaml. "
    "Alternative to --pipeline/--project.",
)
@click.option(
    "--pipeline",
    default=None,
    type=click.Path(exists=True),
    help="Resolved pipeline lock file. Use with --project to locate the project.",
)
@click.option(
    "--project",
    "project_name",
    default=None,
    help="Project name to look up in --pipeline.",
)
@click.pass_context
def main(
    ctx: click.Context,
    project_dir: str | None,
    pipeline: str | None,
    project_name: str | None,
) -> None:
    """Deploy a propeller project based on its project.yaml.

    Locate the project either directly with --project-dir, or by name within a
    resolved pipeline using --pipeline and --project.
    """
    ctx.ensure_object(dict)

    if pipeline and project_name:
        project_dir_path = resolve_project_dir(Path(pipeline), project_name)
    elif project_dir:
        project_dir_path = Path(project_dir).resolve()
    else:
        raise click.UsageError(
            "Provide either --project-dir, or both --pipeline and --project."
        )

    project = load_project_yaml(project_dir_path)
    inputs = collect_inputs()
    propeller_tags, consumer_tags = collect_tags()

    log(f"Project: {project['name']}")
    for var_name, value in inputs.items():
        log(f"Input: {var_name} = {value}")
    for k, v in propeller_tags.items():
        log(f"Tag (framework): {k} = {v}")
    for k, v in consumer_tags.items():
        log(f"Tag (consumer):  {k} = {v}")

    ctx.obj["runner"] = get_runner(
        project, project_dir_path, inputs, propeller_tags, consumer_tags
    )


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


@main.command(name="project-dir")
@click.pass_context
def project_dir_cmd(ctx: click.Context) -> None:
    """Print the resolved project directory (for scripts/buildspecs)."""
    click.echo(str(ctx.obj["runner"].project_dir))
