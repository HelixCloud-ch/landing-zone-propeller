"""Assemble a self-contained deployment bundle from a resolved pipeline."""

from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import yaml

from ..models import Pipeline

MODULE_SOURCE_RE = re.compile(r'(source\s*=\s*")(.*?/\.propeller/modules/)([^"]+)(")')


def rewrite_module_paths(project_dir: Path) -> None:
    # In the bundle, tf files live at projects/<name>/terraform/*.tf and modules
    # at modules/<name>/, so .propeller/modules/ refs become ../../../modules/.
    for tf_file in project_dir.rglob("*.tf"):
        content = tf_file.read_text()
        new_content = MODULE_SOURCE_RE.sub(r"\g<1>../../../modules/\3\4", content)
        if new_content != content:
            tf_file.write_text(new_content)


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


def create_bundle(
    pipeline_path: Path,
    propeller_dir: Path,
    config_dir: Path,
    output_path: Path,
) -> None:
    """Assemble the deployment bundle zip."""
    data = yaml.safe_load(pipeline_path.read_text())
    pipeline = Pipeline(**data)

    with tempfile.TemporaryDirectory() as tmp:
        build = Path(tmp) / "bundle"
        build.mkdir()

        # Projects
        projects_out = build / "projects"
        projects_out.mkdir()
        for stage in pipeline.stages:
            for step in stage.steps:
                src = Path(step.source) if step.source else None
                if src and src.is_dir():
                    dest = projects_out / step.project
                    shutil.copytree(src, dest)
                    rewrite_module_paths(dest)

        # Modules
        modules_src = propeller_dir / "modules"
        if modules_src.is_dir():
            shutil.copytree(modules_src, build / "modules")

        # Config
        if config_dir.is_dir():
            shutil.copytree(config_dir, build / "config")

        # Buildspec
        buildspec_src = propeller_dir / "codebuild"
        if buildspec_src.is_dir():
            shutil.copytree(buildspec_src, build / "codebuild")

        # Engine (for propeller-deploy in CodeBuild)
        engine_src = propeller_dir / "engine"
        if engine_src.is_dir():
            shutil.copytree(
                engine_src,
                build / "engine",
                ignore=shutil.ignore_patterns(".venv", "__pycache__", "*.pyc"),
            )

        # Resolved pipeline
        shutil.copy2(pipeline_path, build / "pipeline-resolved.yaml")

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
