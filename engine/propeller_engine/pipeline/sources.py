"""Resolution of `source:` and `base:` references to on-disk project paths.

Every reference names its namespace. There is no bare form, so a reference cannot
mean different things depending on how the CLI was invoked:

    local:NAME        a project in this repo: a declared `sources:` directory, or
                      the projects/ directory beside the pipeline
    propeller:NAME    a framework project, by name. Names are unique across layers,
                      so `propeller:eks-cluster` means one thing everywhere
    propeller://PATH  deprecated: a path from the framework root

`sources:` in propeller.overrides.yaml lists the consumer directories to search,
relative to that file, in order.
"""

from __future__ import annotations

from pathlib import Path

LOCAL = "local:"
PROPELLER = "propeller:"
PROPELLER_URL = "propeller://"


class SourceError(Exception):
    """A source or base reference that cannot be resolved."""


def consumer_dirs(overrides_path: Path | None, declared: list[str]) -> list[Path]:
    """Consumer source directories, resolved against the overrides file."""
    if not declared:
        return []
    root = overrides_path.parent if overrides_path else Path.cwd()
    return [(root / d).resolve() for d in declared]


def _in_consumer_dirs(name: str, dirs: list[Path]) -> Path | None:
    for d in dirs:
        candidate = d / name
        if (candidate / "project.yaml").is_file():
            return candidate
    return None


def resolve(
    spec: str,
    *,
    consumer: list[Path],
    adjacent: dict[str, dict],
    framework: dict[str, dict],
    framework_root: Path,
) -> str:
    """Resolve one reference to a path.

    `adjacent` and `framework` map a project name to `{"path": ..., "yaml": ...}` for
    consumer projects beside the pipeline and for framework projects respectively.
    """
    if spec.startswith(LOCAL):
        name = spec[len(LOCAL) :]
        found = _in_consumer_dirs(name, consumer)
        if found is not None:
            return str(found)
        entry = adjacent.get(name)
        if entry is not None:
            return entry["path"]
        places = [str(d) for d in consumer] or ["(no sources: declared)"]
        raise SourceError(
            f"'{spec}' not found. Looked in:\n"
            + "\n".join(f"  {p}" for p in places)
            + "\n  the projects/ directory beside the pipeline"
        )

    if spec.startswith(PROPELLER_URL):
        return str(framework_root / spec[len(PROPELLER_URL) :])

    if spec.startswith(PROPELLER):
        name = spec[len(PROPELLER) :]
        entry = framework.get(name)
        if entry is None:
            raise SourceError(
                f"'{spec}' is not a framework project. "
                f"Known names: {', '.join(sorted(framework))}"
            )
        return entry["path"]

    raise SourceError(
        f"'{spec}' has no namespace. Write 'local:{spec}' for a project in this "
        f"repo, or 'propeller:{spec}' for a framework project."
    )
