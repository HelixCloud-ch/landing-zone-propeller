"""Pipeline validation checks."""

from __future__ import annotations

from propeller_engine.models import Pipeline
from propeller_engine.pipeline.validate import (
    validate_depends_on_exist,
    validate_no_cycles,
    validate_no_duplicates,
)


def _pipeline(stages: list[dict]) -> Pipeline:
    return Pipeline(version="1", namespace="t", stages=stages)


def _stage(name: str, *steps: dict) -> dict:
    return {"name": name, "steps": list(steps)}


def test_duplicate_project_across_stages_is_reported():
    """A duplicate name collides on state key, SSM path and overlay directory."""
    pipeline = _pipeline(
        [_stage("a", {"project": "x"}), _stage("b", {"project": "x"})]
    )
    errors = validate_no_duplicates(pipeline)
    assert len(errors) == 1
    assert "'x'" in errors[0] and "'a'" in errors[0] and "'b'" in errors[0]


def test_duplicate_project_within_one_stage_is_reported():
    pipeline = _pipeline([_stage("a", {"project": "x"}, {"project": "x"})])
    assert len(validate_no_duplicates(pipeline)) == 1


def test_distinct_projects_pass():
    pipeline = _pipeline([_stage("a", {"project": "x"}, {"project": "y"})])
    assert validate_no_duplicates(pipeline) == []


def test_depends_on_unknown_project_is_reported():
    pipeline = _pipeline([_stage("a", {"project": "x", "depends_on": ["absent"]})])
    errors = validate_depends_on_exist(pipeline)
    assert len(errors) == 1
    assert "absent" in errors[0]


def test_depends_on_across_stages_is_allowed():
    pipeline = _pipeline(
        [_stage("a", {"project": "x"}), _stage("b", {"project": "y", "depends_on": ["x"]})]
    )
    assert validate_depends_on_exist(pipeline) == []


def test_direct_cycle_is_reported():
    pipeline = _pipeline(
        [
            _stage(
                "a",
                {"project": "x", "depends_on": ["y"]},
                {"project": "y", "depends_on": ["x"]},
            )
        ]
    )
    assert validate_no_cycles(pipeline)


def test_self_dependency_is_reported():
    pipeline = _pipeline([_stage("a", {"project": "x", "depends_on": ["x"]})])
    assert validate_no_cycles(pipeline)


def test_acyclic_chain_passes():
    pipeline = _pipeline(
        [
            _stage(
                "a",
                {"project": "x"},
                {"project": "y", "depends_on": ["x"]},
                {"project": "z", "depends_on": ["y"]},
            )
        ]
    )
    assert validate_no_cycles(pipeline) == []


def test_empty_sources_key_is_tolerated(tmp_path):
    """`sources:` with nothing under it should mean none, not a type error."""
    from propeller_engine.pipeline.resolve import load_overrides

    path = tmp_path / "propeller.overrides.yaml"
    path.write_text("propeller:\n  version: v0\nsources:\npipeline: {}\n")
    assert load_overrides(path).sources == []


def test_every_framework_project_declares_a_name(propeller_dir):
    """A project.yaml with no name is unreachable, so discovery rejects it."""
    import yaml

    root = propeller_dir.parent
    candidates = list(root.glob("*/project.yaml"))
    for layer in root.glob("*/projects"):
        candidates.extend(layer.glob("*/project.yaml"))

    nameless = [
        str(c) for c in candidates if not (yaml.safe_load(c.read_text()) or {}).get("name")
    ]
    assert not nameless, "\n".join(nameless)


def test_framework_project_names_are_unique_across_layers(propeller_dir):
    """`propeller:<name>` is a global identifier, so two layers may not share one."""
    from propeller_engine.pipeline.resolve import _discover_projects

    index = _discover_projects(str(propeller_dir))
    root = propeller_dir.parent
    on_disk = len(list(root.glob("*/project.yaml"))) + sum(
        len(list(layer.glob("*/project.yaml"))) for layer in root.glob("*/projects")
    )
    assert len(index) == on_disk, "a name is declared in two places"
    assert "autopilot" in index, "root-level projects must be reachable by name"
