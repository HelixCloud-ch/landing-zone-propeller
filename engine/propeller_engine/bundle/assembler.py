"""Assemble a self-contained deployment bundle from a resolved pipeline.

The bundle mirrors the source tree 1:1: a pipeline directory like
``landing-zone/`` lands at ``bundle/landing-zone/`` with its internal
structure (``projects/``, ``modules/``, ...) preserved. Any relative path
that resolves in the source resolves the same way in the bundle.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import yaml

from ..models import Pipeline

_IGNORE = shutil.ignore_patterns(".venv", "__pycache__", "*.pyc", ".terraform")


def _get_git_sha() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


def _find_overlay(overlay_dir: Path, project_name: str) -> Path | None:
    """Locate a consumer overlay directory for a project by name."""
    for candidate in overlay_dir.rglob("project.yaml"):
        data = yaml.safe_load(candidate.read_text())
        if data.get("name") == project_name:
            return candidate.parent
    direct = overlay_dir / project_name
    if direct.is_dir():
        return direct
    for d in overlay_dir.rglob(project_name):
        if d.is_dir():
            return d
    return None


def _overlay_onto(dest: Path, overlay_project: Path) -> None:
    """Copy consumer overlay files on top of a project in the bundle."""
    for src_file in overlay_project.rglob("*"):
        if src_file.is_file():
            rel = src_file.relative_to(overlay_project)
            target = dest / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_file, target)


def _bundle_rel(source: Path, propeller_dir: Path, project: str) -> Path:
    """Bundle-relative path for a project source.

    Framework projects keep their location within the mirrored pipeline tree.
    Consumer-only projects (sources outside the framework tree) are placed
    alongside framework projects so relative module references still resolve.
    """
    src = source.resolve()
    pdir = propeller_dir.resolve()
    try:
        return Path(propeller_dir.name) / src.relative_to(pdir)
    except ValueError:
        return Path(propeller_dir.name) / "projects" / project


def create_bundle(
    pipeline_path: Path,
    propeller_dir: Path,
    output_path: Path,
    overlay_dir: Path | None = None,
) -> None:
    """Assemble the deployment bundle zip."""
    data = yaml.safe_load(pipeline_path.read_text())
    pipeline = Pipeline(**data)

    with tempfile.TemporaryDirectory() as tmp:
        build = Path(tmp) / "bundle"
        build.mkdir()

        # Mirror the framework pipeline tree (projects/, modules/, ...) into
        # the bundle under its directory name.
        pipeline_root = build / propeller_dir.name
        if propeller_dir.is_dir():
            shutil.copytree(propeller_dir, pipeline_root, ignore=_IGNORE)

        # Place each step's project at its bundle-relative path, overlay
        # consumer files, and record the bundle-relative source for the runner.
        step_dirs: dict[int, str] = {}
        idx = 0
        for stage in pipeline.stages:
            for step in stage.steps:
                src = Path(step.source) if step.source else None
                rel = _bundle_rel(
                    src if src else propeller_dir / "projects" / step.project,
                    propeller_dir,
                    step.project,
                )
                dest = build / rel
                # Consumer-only project not already inside the mirrored tree.
                if src and src.is_dir() and not dest.exists():
                    shutil.copytree(src, dest, ignore=_IGNORE)
                if overlay_dir:
                    overlay_project = _find_overlay(overlay_dir, step.project)
                    if overlay_project is not None:
                        _overlay_onto(dest, overlay_project)
                step_dirs[idx] = str(rel)
                idx += 1

        # Engine (for propeller-deploy in CodeBuild). Lives at the framework
        # root, not inside the pipeline directory.
        engine_src = (
            propeller_dir.parent / "engine"
            if (propeller_dir.parent / "engine").is_dir()
            else propeller_dir / "engine"
        )
        if engine_src.is_dir():
            shutil.copytree(engine_src, build / "engine", ignore=_IGNORE)

        # Rewrite step sources to bundle-relative paths so the runner can
        # locate each project by source path inside the bundle. Both the YAML
        # and JSON lock files carry the rewritten sources.
        idx = 0
        for stage in data.get("stages", []):
            for step in stage.get("steps", []):
                step["source"] = step_dirs[idx]
                idx += 1
        (build / pipeline_path.name).write_text(
            yaml.dump(data, default_flow_style=False, sort_keys=False)
        )

        json_path = pipeline_path.with_suffix(".json")
        if json_path.exists():
            (build / json_path.name).write_text(json.dumps(data, indent=2) + "\n")
        graph_path = pipeline_path.with_suffix(".md")
        if graph_path.exists():
            shutil.copy2(graph_path, build / graph_path.name)

        # Manifest
        manifest = {
            "propeller_version": pipeline.propeller_version or "unknown",
            "git_sha": _get_git_sha(),
            "bundled_at": datetime.now(timezone.utc).isoformat(),
            "projects": [
                {"name": step.project, "original_source": step.source}
                for stage in pipeline.stages
                for step in stage.steps
            ],
        }
        (build / "MANIFEST.yaml").write_text(
            yaml.dump(manifest, default_flow_style=False, sort_keys=False)
        )

        # Zip
        shutil.make_archive(
            str(output_path.with_suffix("")), "zip", root_dir=tmp, base_dir="bundle"
        )
