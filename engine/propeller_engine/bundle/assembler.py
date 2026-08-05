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

class BundleError(Exception):
    """Assembly cannot proceed."""


_IGNORE = shutil.ignore_patterns(
    ".venv", "__pycache__", "*.pyc", ".terraform", "node_modules", "dist", ".scratch",
    "tests", ".ruff_cache"
)

# The engine ships to CodeBuild to run propeller-deploy; its test suite does not.
_IGNORE_ENGINE = shutil.ignore_patterns(
    ".venv", "__pycache__", "*.pyc", ".terraform", "node_modules", "dist", ".scratch",
    "tests", ".pytest_cache", ".ruff_cache",
)


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

    When a step's project name differs from its source directory name
    (multiple instances of the same source), each gets its own path
    under projects/{project} to avoid overlay collisions.

    Framework projects whose name matches the source keep their original
    location within the mirrored pipeline tree.
    """
    src = source.resolve()
    pdir = propeller_dir.resolve()
    try:
        rel = src.relative_to(pdir)
        # If the project name matches the source directory, keep original path
        if rel.name == project:
            return Path(propeller_dir.name) / rel
        # Different project name = instance of a shared source → unique path
        return Path(propeller_dir.name) / "projects" / project
    except ValueError:
        return Path(propeller_dir.name) / "projects" / project


def create_bundle(
    pipeline_path: Path,
    propeller_dir: Path,
    output_path: Path,
    overlay_dir: Path | None = None,
) -> dict:
    """Assemble the deployment bundle zip and return its manifest."""
    data = yaml.safe_load(pipeline_path.read_text())
    pipeline = Pipeline(**data)

    # shared/ and engine/ are located relative to the framework root, which is
    # propeller_dir's parent. A relative propeller_dir would resolve that against
    # the process cwd and silently omit both from the bundle.
    propeller_dir = propeller_dir.resolve()

    with tempfile.TemporaryDirectory() as tmp:
        build = Path(tmp) / "bundle"
        build.mkdir()

        # Copy only the parts of the framework tree that are needed:
        # 1. shared/ subdirs (modules, recipes referenced by relative path)
        # 2. Individual project dirs for steps that reference framework projects
        # This avoids bundling every framework project regardless of usage.
        pipeline_root = build / propeller_dir.name
        pipeline_root.mkdir(parents=True, exist_ok=True)

        # shared modules (platform/shared/) — always needed for relative imports
        shared_in_pipeline = propeller_dir / "shared"
        if shared_in_pipeline.is_dir():
            shutil.copytree(
                shared_in_pipeline, pipeline_root / "shared", ignore=_IGNORE
            )

        # Collect which framework project dirs are referenced by steps
        referenced_projects: set[Path] = set()
        for stage in pipeline.stages:
            for step in stage.steps:
                src = Path(step.source) if step.source else None
                if src and src.is_dir():
                    resolved = src.resolve()
                    try:
                        resolved.relative_to(propeller_dir.resolve())
                        referenced_projects.add(src)
                    except ValueError:
                        pass  # consumer source, not a framework project
                else:
                    candidate = propeller_dir / "projects" / step.project
                    if candidate.is_dir():
                        referenced_projects.add(candidate)
                # base projects
                if step.base:
                    base_path = Path(step.base)
                    if base_path.is_dir():
                        referenced_projects.add(base_path)

        # Copy only referenced framework project dirs (preserving depth)
        projects_dest = pipeline_root / "projects"
        projects_dest.mkdir(parents=True, exist_ok=True)
        for proj_path in referenced_projects:
            resolved = proj_path.resolve()
            try:
                rel = resolved.relative_to(propeller_dir.resolve())
            except ValueError:
                continue
            dest = pipeline_root / rel
            if not dest.exists():
                shutil.copytree(resolved, dest, ignore=_IGNORE)

        # Place each step's project at its bundle-relative path, overlay
        # consumer files, and record the bundle-relative source for the runner.
        step_dirs: dict[int, str] = {}
        layers: dict[str, list[dict[str, str]]] = {}
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
                applied: list[dict[str, str]] = []
                # Copy source to destination if not already there. A project
                # declaring `base:` gets the base first, then its own files on top.
                if not dest.exists():
                    source_path = src if src and src.is_dir() else propeller_dir / "projects" / step.project
                    base_path = Path(step.base) if step.base else None
                    if base_path is not None and base_path.is_dir():
                        shutil.copytree(base_path, dest, ignore=_IGNORE)
                        applied.append({"kind": "base", "from": str(base_path)})
                        if source_path.is_dir():
                            _overlay_onto(dest, source_path)
                            applied.append({"kind": "source", "from": str(source_path)})
                    elif source_path.is_dir():
                        shutil.copytree(source_path, dest, ignore=_IGNORE)
                        applied.append({"kind": "source", "from": str(source_path)})
                    else:
                        raise BundleError(
                            f"project '{step.project}' has no source on disk: tried {source_path}"
                        )
                # Resolved during pipeline resolution, applied in order.
                for overlay in step.overlays:
                    _overlay_onto(dest, Path(overlay))
                    applied.append({"kind": "overlay", "from": overlay})
                step_dirs[idx] = str(rel)
                layers[step.project] = applied
                idx += 1

        # Engine (for propeller-deploy in CodeBuild). Lives at the framework
        # root, not inside the pipeline directory.
        engine_src = (
            propeller_dir.parent / "engine"
            if (propeller_dir.parent / "engine").is_dir()
            else propeller_dir / "engine"
        )
        if engine_src.is_dir():
            shutil.copytree(engine_src, build / "engine", ignore=_IGNORE_ENGINE)

        # Shared recipes (justfile imports). Lives at the framework root as
        # shared/recipes/. Copied into the bundle so project justfiles can
        # import "../../shared/recipes/terraform.just".
        shared_src = (
            propeller_dir.parent / "shared"
            if (propeller_dir.parent / "shared").is_dir()
            else propeller_dir / "shared"
        )
        if shared_src.is_dir():
            shutil.copytree(shared_src, build / "shared", ignore=_IGNORE)

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

        # Overlay directories that matched no project. Legitimate for a filtered
        # pipeline, and a typo otherwise, so reported rather than fatal.
        unused: list[str] = []
        if overlay_dir:
            applied_from = {
                layer["from"]
                for project_layers in layers.values()
                for layer in project_layers
                if layer["kind"] == "overlay"
            }
            candidates = sorted(p for p in overlay_dir.iterdir() if p.is_dir())
            if candidates and not applied_from and not pipeline.overlays:
                raise BundleError(
                    f"{overlay_dir} holds directories but the pipeline declares no "
                    f"overlays, so none would be applied. Add "
                    f"'overlays: [{overlay_dir.name}/${{project}}]' to the "
                    f"pipeline, or to individual steps."
                )
            for candidate in candidates:
                if str(candidate) not in applied_from:
                    unused.append(str(candidate))

        # Manifest
        manifest = {
            "propeller_version": pipeline.propeller_version or "unknown",
            "git_sha": _get_git_sha(),
            "bundled_at": datetime.now(timezone.utc).isoformat(),
            "unused_overlays": unused,
            "projects": [
                {
                    "name": step.project,
                    "resolved_source": step.source,
                    "bundle_path": step_dirs[i],
                    "layers": layers.get(step.project, []),
                }
                for i, step in enumerate(
                    s for stage in pipeline.stages for s in stage.steps
                )
            ],
        }
        (build / "MANIFEST.yaml").write_text(
            yaml.dump(manifest, default_flow_style=False, sort_keys=False)
        )

        # Zip
        shutil.make_archive(
            str(output_path.with_suffix("")), "zip", root_dir=tmp, base_dir="bundle"
        )

    return manifest
