"""CLI: propeller-bundle"""

from pathlib import Path

import click

from ..bundle import create_bundle


@click.command()
@click.option("--pipeline", required=True, type=click.Path(exists=True))
@click.option("--propeller-dir", required=True, type=click.Path(exists=True))
@click.option(
    "--overlay-dir",
    default=None,
    type=click.Path(exists=True),
    help="Directory with consumer project overlays (*.auto.tfvars, overrides.tf, etc.)",
)
@click.option("--output", required=True, type=click.Path())
def main(
    pipeline: str, propeller_dir: str, overlay_dir: str | None, output: str
) -> None:
    """Bundle the resolved pipeline into a deployable zip artifact."""
    create_bundle(
        pipeline_path=Path(pipeline),
        propeller_dir=Path(propeller_dir),
        output_path=Path(output),
        overlay_dir=Path(overlay_dir) if overlay_dir else None,
    )
    click.echo(f"Bundle created → {output}")
