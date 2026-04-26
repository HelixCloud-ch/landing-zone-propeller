"""CLI: propeller-validate"""

from pathlib import Path

import click
import yaml

from ..models import Pipeline
from ..pipeline import validate_pipeline


@click.command()
@click.option(
    "--pipeline",
    required=True,
    type=click.Path(exists=True),
    help="Resolved pipeline YAML",
)
@click.option(
    "--check-sources/--no-check-sources", default=True, help="Verify source paths exist"
)
def main(pipeline: str, check_sources: bool) -> None:
    """Validate a resolved pipeline."""
    data = yaml.safe_load(Path(pipeline).read_text())
    p = Pipeline(**data)
    errors = validate_pipeline(p, check_sources=check_sources)

    if errors:
        click.echo("Validation FAILED:", err=True)
        for e in errors:
            click.echo(f"  ✗ {e}", err=True)
        raise SystemExit(1)

    total = sum(len(s.steps) for s in p.stages)
    click.echo(f"Validation passed — {total} projects across {len(p.stages)} stages")
