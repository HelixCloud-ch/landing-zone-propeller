"""Shared fixtures for engine tests.

Resolve and assembly run against a real filesystem under `tmp_path`. No AWS, no
credentials, no network.
"""

from __future__ import annotations

import shutil
import subprocess
import zipfile
from pathlib import Path

import pytest
import yaml

FIXTURES = Path(__file__).parent / "fixtures"
GOLDEN = Path(__file__).parent / "golden"
FRAMEWORK_ROOT = Path(__file__).resolve().parents[2]


def _have(binary: str) -> bool:
    return shutil.which(binary) is not None


needs_just = pytest.mark.skipif(not _have("just"), reason="just not on PATH")


@pytest.fixture
def consumer(tmp_path: Path) -> Path:
    """A writable copy of the fixture consumer repo, one per test."""
    dest = tmp_path / "consumer"
    shutil.copytree(FIXTURES / "consumer", dest)
    return dest


@pytest.fixture
def propeller_dir() -> Path:
    """The framework platform tree."""
    return FRAMEWORK_ROOT / "platform"


@pytest.fixture
def pipeline_path(consumer: Path) -> Path:
    return consumer / "platforms" / "main" / "pipeline.yaml"


@pytest.fixture
def overrides_path(consumer: Path) -> Path:
    return consumer / "propeller.overrides.yaml"


def bundle_tree(zip_path: Path) -> list[str]:
    """Sorted bundle-relative paths inside a bundle zip."""
    with zipfile.ZipFile(zip_path) as zf:
        names = [n for n in zf.namelist() if not n.endswith("/")]
    prefix = "bundle/"
    return sorted(n[len(prefix) :] if n.startswith(prefix) else n for n in names)


def bundle_read(zip_path: Path, rel: str) -> str:
    with zipfile.ZipFile(zip_path) as zf:
        return zf.read(f"bundle/{rel}").decode()


def bundle_manifest(zip_path: Path) -> dict:
    return yaml.safe_load(bundle_read(zip_path, "MANIFEST.yaml"))


def extract(zip_path: Path, dest: Path) -> Path:
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(dest)
    return dest / "bundle"


def just_summary(project_dir: Path) -> subprocess.CompletedProcess:
    """Parse a project's justfile and its imports.

    `--summary` resolves imports without evaluating variables, so a justfile reading
    env vars it only has at deploy time still parses.
    """
    return subprocess.run(
        ["just", "--justfile", str(project_dir / "justfile"), "--summary"],
        capture_output=True,
        text=True,
        cwd=project_dir,
    )



def pytest_addoption(parser):
    parser.addoption(
        "--update-golden",
        action="store_true",
        help="Rewrite golden files instead of comparing against them.",
    )
    parser.addoption(
        "--keep-bundle",
        action="store_true",
        help="Also write the assembled bundle to engine/.scratch/ for inspection.",
    )


@pytest.fixture
def update_golden(request) -> bool:
    return request.config.getoption("--update-golden")


@pytest.fixture
def keep_bundle(request) -> bool:
    return request.config.getoption("--keep-bundle")


SCRATCH = Path(__file__).resolve().parents[1] / ".scratch"


def compare_golden(name: str, actual: str, update: bool) -> None:
    """Compare against a committed golden file, or rewrite it."""
    path = GOLDEN / name
    if update:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(actual)
        return
    assert path.is_file(), (
        f"missing golden {path.name}; run `pytest --update-golden` to create it"
    )
    assert actual == path.read_text(), (
        f"{path.name} differs from the assembled result; "
        "review the change and rerun with --update-golden to accept it"
    )
