"""Bundle assembly: path allocation, overlay layering, tree shape.

Unimplemented behaviour is marked `xfail(strict=True)`, so the marker fails once the
feature lands and has to be removed.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

import pytest

import yaml

from propeller_engine.bundle.assembler import BundleError, _bundle_rel, create_bundle
from propeller_engine.pipeline import pipeline_to_dict, resolve

from . import report
from .conftest import (
    SCRATCH,
    bundle_manifest,
    bundle_read,
    bundle_tree,
    extract,
    compare_golden,
    just_summary,
    needs_just,
)

# ── Pure: path allocation ─────────────────────────────────────────────────────


def test_bundle_rel_keeps_mirrored_path_when_name_matches():
    """A project deployed under its source name keeps the mirrored path."""
    pdir = Path("/fw/platform")
    rel = _bundle_rel(pdir / "projects" / "vpc", pdir, "vpc")
    assert rel == Path("platform/projects/vpc")


def test_bundle_rel_gives_instances_unique_paths():
    """Two instances of one source get separate bundle paths."""
    pdir = Path("/fw/platform")
    one = _bundle_rel(pdir / "projects" / "store", pdir, "store-one")
    two = _bundle_rel(pdir / "projects" / "store", pdir, "store-two")
    assert one != two
    assert one == Path("platform/projects/store-one")


def test_bundle_rel_handles_source_outside_propeller_dir():
    """A consumer source lives outside the framework tree entirely."""
    rel = _bundle_rel(Path("/repo/sources/store"), Path("/fw/platform"), "store-one")
    assert rel == Path("platform/projects/store-one")


def test_bundle_rel_depth_is_uniform():
    """Every project lands three levels deep.

    Project justfiles import "../../../shared/recipes/terraform.just" and shared/ is
    copied to the bundle root, so the depth has to be uniform.
    """
    pdir = Path("/fw/platform")
    cases = [
        _bundle_rel(pdir / "projects" / "vpc", pdir, "vpc"),
        _bundle_rel(pdir / "projects" / "store", pdir, "store-one"),
        _bundle_rel(Path("/repo/sources/store"), pdir, "store-two"),
    ]
    assert {len(c.parts) for c in cases} == {3}


# ── Assembly: tree shape ──────────────────────────────────────────────────────


@pytest.fixture
def lock(tmp_path, pipeline_path, overrides_path, propeller_dir):
    """The resolved lock file, which is what the bundler consumes."""
    pipeline = resolve(
        pipeline_path, overrides_path, str(propeller_dir), version="v0.0.0-fixture"
    )
    path = tmp_path / "pipeline.lock.yaml"
    path.write_text(yaml.dump(pipeline_to_dict(pipeline), sort_keys=False))
    return path


@pytest.fixture
def assembled(tmp_path, consumer, propeller_dir, lock):
    """Bundle the fixture consumer with its overlays."""
    out = tmp_path / "bundle.zip"
    create_bundle(
        pipeline_path=lock,
        propeller_dir=propeller_dir,
        output_path=out,
        overlay_dir=consumer / "overlays",
    )
    return out


def test_shared_recipes_land_at_bundle_root(assembled):
    """The import target for project justfiles."""
    assert "shared/recipes/terraform.just" in bundle_tree(assembled)


def test_every_project_in_the_manifest(assembled):
    names = {p["name"] for p in bundle_manifest(assembled)["projects"]}
    assert names == {
        "lookup",
        "store-one",
        "store-two",
        "store-one-archive",
        "store-tuned-one",
        "cache-one",
        "service-one",
        "local-smoke",
        "framework-smoke",
        "framework-smoke-legacy",
        "smoke-test",
        "adjacent-implicit",
        "adjacent-named",
    }


def test_instances_of_one_source_get_separate_directories(assembled):
    tree = bundle_tree(assembled)
    assert any(p.startswith("platform/projects/store-one/") for p in tree)
    assert any(p.startswith("platform/projects/store-two/") for p in tree)


def test_project_without_terraform_assembles(assembled):
    """`service` ships a justfile and no terraform."""
    tree = bundle_tree(assembled)
    assert "platform/projects/service-one/justfile" in tree
    assert not any(p.startswith("platform/projects/service-one/terraform/") for p in tree)


# ── Assembly: overlays ────────────────────────────────────────────────────────


def test_overlay_applies_to_its_own_instance(assembled):
    body = bundle_read(assembled, "platform/projects/store-one/terraform/override.auto.tfvars")
    assert 'size = "large"' in body


def test_overlay_does_not_leak_to_prefix_named_sibling(assembled):
    """`_find_overlay` matches by directory name, so prefixes can collide."""
    archive = bundle_read(
        assembled, "platform/projects/store-one-archive/terraform/override.auto.tfvars"
    )
    assert 'label = "archive"' in archive
    assert "size" not in archive


def test_base_project_files_are_inherited(assembled):
    """`store-tuned` declares `base: store` and ships no justfile or main.tf."""
    tree = bundle_tree(assembled)
    assert "platform/projects/store-tuned-one/justfile" in tree
    assert "platform/projects/store-tuned-one/terraform/main.tf" in tree


def test_overlay_shadows_base_file(assembled):
    """Layer order: base, consumer source, overlay."""
    body = bundle_read(
        assembled, "platform/projects/store-tuned-one/terraform/config.auto.tfvars"
    )
    assert 'size = "large"' in body


# ── Assembly: source schemes (not implemented) ────────────────────────────────


def test_bare_name_resolves_to_consumer_copy(assembled):
    """A bare name picks the consumer project."""
    body = bundle_read(assembled, "platform/projects/local-smoke/justfile")
    assert 'marker := "consumer"' in body


def test_explicit_framework_scheme_bypasses_the_consumer_copy(assembled):
    body = bundle_read(assembled, "platform/projects/framework-smoke/justfile")
    assert 'marker := "consumer"' not in body


# ── Determinism ───────────────────────────────────────────────────────────────


def test_bundle_tree_is_stable_across_runs(tmp_path, consumer, propeller_dir, lock):
    """Zip bytes are not compared: entry mtimes vary between runs."""
    trees = []
    for i in range(2):
        out = tmp_path / f"b{i}.zip"
        create_bundle(
            pipeline_path=lock,
            propeller_dir=propeller_dir,
            output_path=out,
            overlay_dir=consumer / "overlays",
        )
        trees.append(bundle_tree(out))
    assert trees[0] == trees[1]


# ── Usability of the assembled bundle ─────────────────────────────────────────


@needs_just
def test_assembled_justfiles_parse(tmp_path, assembled):
    """Catches broken relative imports after path rewriting."""
    root = extract(assembled, tmp_path / "x")
    failures = []
    for justfile in sorted(root.glob("platform/projects/*/justfile")):
        result = just_summary(justfile.parent)
        if result.returncode != 0:
            failures.append(f"{justfile.parent.name}: {result.stderr.strip()}")
    assert not failures, "\n".join(failures)



def test_tfvars_only_set_declared_variables(tmp_path, assembled):
    """A shadowed variables.tf that drops a variable still set in tfvars.

    Structural stand-in for `terraform validate`: no provider downloads, no network.
    """
    root = extract(assembled, tmp_path / "vars")
    problems = []
    for tf_dir in sorted(root.glob("platform/projects/*/terraform")):
        declared = set()
        for tf in tf_dir.glob("*.tf"):
            declared |= set(re.findall(r'^variable\s+"([^"]+)"', tf.read_text(), re.M))
        for tfvars in tf_dir.glob("*.auto.tfvars"):
            for line in tfvars.read_text().splitlines():
                m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*=", line)
                if m and m.group(1) not in declared:
                    problems.append(f"{tf_dir.parent.name}: {tfvars.name} sets undeclared {m.group(1)}")
    assert not problems, "\n".join(problems)



def test_shared_and_engine_survive_a_relative_propeller_dir(
    tmp_path, monkeypatch, consumer, propeller_dir, lock
):
    """Both are located relative to the framework root, not the process cwd."""
    monkeypatch.chdir(propeller_dir.parent)
    out = tmp_path / "relative.zip"
    create_bundle(
        pipeline_path=lock,
        propeller_dir=Path(propeller_dir.name),
        output_path=out,
        overlay_dir=consumer / "overlays",
    )
    tree = bundle_tree(out)
    assert "shared/recipes/terraform.just" in tree
    assert any(p.startswith("engine/") for p in tree)



def test_manifest_records_the_layers_applied(assembled):
    """Which layers a project was built from, and where each came from."""
    projects = {p["name"]: p for p in bundle_manifest(assembled)["projects"]}

    def kinds(name: str) -> list[str]:
        return [layer["kind"] for layer in projects[name]["layers"]]

    assert kinds("cache-one") == ["source"]
    assert kinds("store-one") == ["source", "overlay", "overlay"]
    assert kinds("store-one-archive") == ["source", "overlay"]
    assert kinds("store-tuned-one") == ["base", "source"]

    tuned = projects["store-tuned-one"]["layers"]
    assert tuned[0]["from"].endswith("/sources/store")
    assert tuned[1]["from"].endswith("/sources/store-tuned")


def test_manifest_records_the_bundle_path(assembled):
    projects = {p["name"]: p for p in bundle_manifest(assembled)["projects"]}
    assert projects["store-one"]["bundle_path"] == "platform/projects/store-one"


def test_manifest_records_declared_overlays_in_order(assembled):
    """Order decides which wins, so it has to be visible rather than inferred."""
    projects = {p["name"]: p for p in bundle_manifest(assembled)["projects"]}
    overlays = [
        layer["from"]
        for layer in projects["store-one"]["layers"]
        if layer["kind"] == "overlay"
    ]
    assert [Path(o).parent.name for o in overlays] == ["org-overlays", "overlays"]


def test_the_last_declared_overlay_wins(assembled):
    """Both overlays hold config.auto.tfvars; the one written second must survive."""
    body = bundle_read(
        assembled, "platform/projects/store-one/terraform/config.auto.tfvars"
    )
    assert 'label = "tenant"' in body
    assert 'label = "org"' not in body


def test_a_declared_overlay_that_is_absent_is_skipped(resolved_overlays):
    """Most instances have no overlay, so a pattern is not a promise."""
    assert resolved_overlays["store-two"] == []


def test_unresolvable_source_fails_the_bundle(tmp_path, consumer, propeller_dir, lock):
    """An empty project directory in the bundle would only surface in CodeBuild."""
    data = yaml.safe_load(lock.read_text())
    data["stages"][0]["steps"][0]["source"] = str(tmp_path / "absent")
    lock.write_text(yaml.dump(data, sort_keys=False))
    with pytest.raises(BundleError, match="has no source on disk"):
        create_bundle(
            pipeline_path=lock,
            propeller_dir=propeller_dir,
            output_path=tmp_path / "fail.zip",
            overlay_dir=consumer / "overlays",
        )



def test_engine_ships_without_its_test_suite(assembled):
    """The engine runs propeller-deploy in CodeBuild; its tests are not needed there."""
    tree = bundle_tree(assembled)
    assert any(p.startswith("engine/propeller_engine/") for p in tree)
    assert not any(p.startswith("engine/tests/") for p in tree)
    assert not any(".pytest_cache" in p for p in tree)



def test_assembly_report_matches_golden(
    tmp_path, assembled, consumer, propeller_dir, update_golden, keep_bundle
):
    """Per-file provenance across every project, as a reviewable diff.

    Run with --keep-bundle to leave the extracted bundle in engine/.scratch/.
    """
    root = extract(assembled, tmp_path / "report")
    cases = yaml.safe_load((consumer / "cases.yaml").read_text())
    authored = yaml.safe_load(
        (consumer / "platforms" / "main" / "pipeline.yaml").read_text()
    )
    specs = {
        s["project"]: s["source"]
        for stage in authored["stages"]
        for s in stage["steps"]
        if s.get("source")
    }
    actual = report.build(
        bundle_manifest(assembled),
        root,
        {"consumer": consumer, "framework": propeller_dir.parent},
        cases,
        specs,
    )
    if keep_bundle:
        if SCRATCH.exists():
            shutil.rmtree(SCRATCH)
        SCRATCH.mkdir(parents=True)
        shutil.copytree(root, SCRATCH / "bundle")
        shutil.copy2(assembled, SCRATCH / "bundle.zip")
        (SCRATCH / "report.md").write_text(actual)
    compare_golden("bundle-report.md", actual, update_golden)


def test_bundle_tree_structure(assembled):
    """Bundle has shared recipes, engine, and at least one shared module."""
    tree = bundle_tree(assembled)
    assert "shared/recipes/terraform.just" in tree
    assert any(p.startswith("platform/shared/modules/") for p in tree)
    assert any(p.startswith("engine/") for p in tree)
    assert "pipeline.lock.yaml" in tree


def test_framework_project_under_its_own_name_keeps_the_mirrored_path(assembled):
    """Already present from the tree mirror, so it is not copied again."""
    projects = {p["name"]: p for p in bundle_manifest(assembled)["projects"]}
    assert projects["smoke-test"]["bundle_path"] == "platform/projects/smoke-test"
    assert [l["kind"] for l in projects["smoke-test"]["layers"]] == ["overlay"]


def test_overlay_applies_to_a_mirrored_framework_project(assembled):
    body = bundle_read(
        assembled, "platform/projects/smoke-test/terraform/override.auto.tfvars"
    )
    assert 'region = "eu-central-2"' in body


def test_every_fixture_project_has_a_recorded_case(tmp_path, assembled, consumer, propeller_dir):
    """A project added to the fixture must say what it exercises."""
    root = extract(assembled, tmp_path / "cases")
    with pytest.raises(KeyError, match="no case recorded"):
        report.build(
            bundle_manifest(assembled),
            root,
            {"consumer": consumer, "framework": propeller_dir.parent},
            cases={},
        )


def test_root_level_asset_lands_at_the_uniform_depth():
    """A source outside any layer directory, such as autopilot at the framework root."""
    rel = _bundle_rel(Path("/fw/autopilot"), Path("/fw/platform"), "autopilot")
    assert rel == Path("platform/projects/autopilot")
    assert len(rel.parts) == 3


def test_build_outputs_and_dependencies_are_not_bundled(assembled):
    """Stripped on purpose: projects that need them rebuild in CodeBuild.

    autopilot ships a `dist/` and `node_modules/` locally, and its justfile runs
    `pnpm install && pnpm run build` before plan and apply.
    """
    tree = bundle_tree(assembled)
    assert not any("/node_modules/" in p for p in tree)
    assert not any("/dist/" in p for p in tree)


def test_overlay_matching_no_project_is_reported(tmp_path, consumer, propeller_dir, lock):
    """A typo in an overlay directory name is otherwise silent."""
    stray = consumer / "overlays" / "store-typo"
    (stray / "terraform").mkdir(parents=True)
    (stray / "terraform" / "override.auto.tfvars").write_text("size = \"large\"\n")
    out = tmp_path / "stray.zip"
    manifest = create_bundle(
        pipeline_path=lock,
        propeller_dir=propeller_dir,
        output_path=out,
        overlay_dir=consumer / "overlays",
    )
    assert manifest["unused_overlays"] == [str(stray)]


def test_no_unused_overlays_when_every_directory_matches(assembled):
    assert bundle_manifest(assembled)["unused_overlays"] == []


@pytest.fixture
def resolved_overlays(pipeline_path, overrides_path, propeller_dir):
    pipeline = resolve(pipeline_path, overrides_path, str(propeller_dir))
    return {s.project: list(s.overlays) for st in pipeline.stages for s in st.steps}


def test_declared_overlay_patterns_resolve_to_existing_directories(resolved_overlays):
    assert [Path(p).parent.name for p in resolved_overlays["store-one"]] == [
        "org-overlays",
        "overlays",
    ]
    assert [Path(p).name for p in resolved_overlays["store-one"]] == [
        "store-one",
        "store-one",
    ]



def test_overlay_dir_without_declared_overlays_is_an_error(
    tmp_path, consumer, pipeline_path, overrides_path, propeller_dir
):
    """Overlays are applied only where declared, so a pipeline that names none
    would silently drop every directory it was given."""
    data = yaml.safe_load(pipeline_path.read_text())
    data.pop("overlays")
    for stage in data["stages"]:
        for step in stage["steps"]:
            step.pop("overlays", None)
    pipeline_path.write_text(yaml.dump(data, sort_keys=False))

    pipeline = resolve(
        pipeline_path, overrides_path, str(propeller_dir), version="v0.0.0-fixture"
    )
    lock_path = tmp_path / "bare.lock.yaml"
    lock_path.write_text(yaml.dump(pipeline_to_dict(pipeline), sort_keys=False))

    with pytest.raises(BundleError, match="declares no overlays"):
        create_bundle(
            pipeline_path=lock_path,
            propeller_dir=propeller_dir,
            output_path=tmp_path / "bare.zip",
            overlay_dir=consumer / "overlays",
        )
