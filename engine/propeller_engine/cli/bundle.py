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
    help="Overlay root, checked for directories the pipeline never applies. "
    "Which overlays apply is decided by the pipeline's own overlays: patterns.",
)
@click.option("--output", required=True, type=click.Path())
@click.option("-v", "--verbose", is_flag=True, help="Report each layer applied per project.")
def main(
    pipeline: str,
    propeller_dir: str,
    overlay_dir: str | None,
    output: str,
    verbose: bool,
) -> None:
    """Bundle the resolved pipeline into a deployable zip artifact."""
    manifest = create_bundle(
        pipeline_path=Path(pipeline),
        propeller_dir=Path(propeller_dir),
        output_path=Path(output),
        overlay_dir=Path(overlay_dir) if overlay_dir else None,
    )
    for project in manifest["projects"]:
        kinds = "+".join(layer["kind"] for layer in project["layers"])
        click.echo(f"  {project['name']:<32} {project['bundle_path']}  [{kinds}]")
        if verbose:
            for layer in project["layers"]:
                click.echo(f"      {layer['kind']:<8} {layer['from']}")
    for path in manifest.get("unused_overlays", []):
        click.echo(f"  warning: overlay matched no project: {path}", err=True)
    click.echo(f"Bundle created → {output}")
