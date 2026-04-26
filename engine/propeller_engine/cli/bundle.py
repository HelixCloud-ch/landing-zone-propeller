"""CLI: propeller-bundle"""

from pathlib import Path

import click

from ..bundle import create_bundle


@click.command()
@click.option("--pipeline", required=True, type=click.Path(exists=True))
@click.option("--propeller-dir", required=True, type=click.Path(exists=True))
@click.option("--config-dir", required=True, type=click.Path(exists=True))
@click.option("--output", required=True, type=click.Path())
def main(pipeline: str, propeller_dir: str, config_dir: str, output: str) -> None:
    """Bundle the resolved pipeline into a deployable zip artifact."""
    create_bundle(
        pipeline_path=Path(pipeline),
        propeller_dir=Path(propeller_dir),
        config_dir=Path(config_dir),
        output_path=Path(output),
    )
    click.echo(f"Bundle created → {output}")
