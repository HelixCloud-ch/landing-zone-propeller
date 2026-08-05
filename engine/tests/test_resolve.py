"""Pipeline resolution: source provenance, input and output expansion, references.

Unimplemented behaviour is marked `xfail(strict=True)`, so the marker fails once the
feature lands and has to be removed.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from propeller_engine.pipeline import pipeline_to_dict, resolve
from propeller_engine.pipeline.sources import SourceError
from propeller_engine.pipeline.sources import resolve as sources_resolve


def _steps(pipeline) -> dict:
    return {s.project: s for stage in pipeline.stages for s in stage.steps}


def _field(entry, name):
    return entry.get(name) if isinstance(entry, dict) else getattr(entry, name, None)


def _by_var(step, var):
    return next(i for i in step.inputs if _field(i, "var") == var)


@pytest.fixture
def resolved(pipeline_path, overrides_path, propeller_dir):
    return resolve(
        pipeline_path, overrides_path, str(propeller_dir), version="v0.0.0-fixture"
    )


def test_every_step_survives_resolution(resolved):
    assert set(_steps(resolved)) == {
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


def test_stage_barriers_are_preserved(resolved):
    assert {s.name: s.barrier for s in resolved.stages} == {
        "discover": True,
        "stateful": False,
        "apps": True,
        "collision": True,
        "adjacent": True,
    }


def test_runner_is_carried_through(resolved):
    assert _steps(resolved)["service-one"].runner == "deploy-runner-vpc-app"


def test_version_is_stamped(resolved):
    assert resolved.propeller_version == "v0.0.0-fixture"


def test_output_resolves_to_a_blob_field(resolved):
    outputs = _steps(resolved)["lookup"].outputs
    assert [_field(o, "field") for o in outputs] == ["net_id", "subnet_ids_json"]
    assert {_field(o, "key") for o in outputs} == {"/propeller/fixture/lookup"}


def test_blob_input_resolves_to_the_producing_project(resolved):
    net_id = _by_var(_steps(resolved)["store-one"], "net_id")
    assert _field(net_id, "key") == "/propeller/fixture/lookup"
    assert _field(net_id, "field") == "net_id"


def test_literal_input_carries_a_literal_and_no_key(resolved):
    identifier = _by_var(_steps(resolved)["store-one"], "identifier")
    assert _field(identifier, "literal") == "store-one"
    assert _field(identifier, "key") is None


def test_literal_inputs_survive_serialisation(resolved):
    data = pipeline_to_dict(resolved)
    steps = {s["project"]: s for st in data["stages"] for s in st["steps"]}
    identifier = next(
        i for i in steps["store-one"]["inputs"] if i.get("var") == "identifier"
    )
    assert identifier == {"var": "identifier", "literal": "store-one"}


def test_resolution_is_deterministic(pipeline_path, overrides_path, propeller_dir):
    runs = []
    for _ in range(2):
        data = pipeline_to_dict(
            resolve(pipeline_path, overrides_path, str(propeller_dir), version="v0.0.0-fixture")
        )
        data.pop("resolved_at")
        runs.append(data)
    assert runs[0] == runs[1]


@pytest.mark.xfail(strict=True, reason="${vars.*} interpolation not implemented")
def test_interpolated_input_is_substituted_at_resolve_time(
    pipeline_path, overrides_path, propeller_dir
):
    pipeline = resolve(
        pipeline_path,
        overrides_path,
        str(propeller_dir),
        version="v0.0.0-fixture",
        vars={"vars": {"label": "fixture"}},
    )
    assert _field(_by_var(_steps(pipeline)["store-one"], "label"), "literal") == "fixture-one"


@pytest.mark.xfail(strict=True, reason="drop-on-unresolved not implemented")
def test_unresolved_reference_drops_the_input(resolved):
    assert not [i for i in _steps(resolved)["store-one"].inputs if _field(i, "var") == "label"]


def test_bare_name_prefers_the_consumer_source(resolved, consumer):
    assert str(_steps(resolved)["local-smoke"].source) == str(
        consumer / "sources" / "smoke-test"
    )


def test_local_scheme_resolves_to_the_consumer_source(resolved, consumer):
    assert str(_steps(resolved)["store-two"].source) == str(consumer / "sources" / "store")


def test_propeller_scheme_resolves_from_the_framework_root(resolved, propeller_dir):
    assert str(_steps(resolved)["framework-smoke"].source) == str(
        propeller_dir / "projects" / "smoke-test"
    )


@pytest.mark.xfail(strict=True, reason="output validation not implemented")
def test_output_absent_from_the_project_is_rejected(
    pipeline_path, overrides_path, propeller_dir
):
    from propeller_engine.pipeline import validate_outputs

    pipeline = resolve(pipeline_path, overrides_path, str(propeller_dir))
    with pytest.raises(ValueError, match="does not publish"):
        validate_outputs(pipeline)


def test_absolute_input_reads_an_individual_parameter(resolved):
    account_id = _by_var(_steps(resolved)["service-one"], "account_id")
    assert _field(account_id, "key") == "/propeller/accounts/acct-primary/id"
    assert _field(account_id, "field") is None


def test_cross_pipeline_input_reads_another_namespace_blob(resolved):
    hub_id = _by_var(_steps(resolved)["service-one"], "hub_id")
    assert _field(hub_id, "key") == "/propeller/other-pipeline/net"
    assert _field(hub_id, "field") == "hub_id"


def test_cross_pipeline_input_without_a_field_is_rejected(consumer, overrides_path, propeller_dir):
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(path.read_text().replace('"@other-pipeline/net.hub_id"', '"@other-pipeline/net"'))
    with pytest.raises(Exception, match="must include a field"):
        resolve(path, overrides_path, str(propeller_dir))


def test_deprecated_propeller_url_alias_still_resolves(resolved, propeller_dir):
    assert str(_steps(resolved)["framework-smoke-legacy"].source) == str(
        propeller_dir / "projects" / "smoke-test"
    )


def test_local_scheme_with_no_match_is_rejected(consumer, overrides_path, propeller_dir):
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(path.read_text().replace("source: local:store", "source: local:absent"))
    with pytest.raises(SourceError, match="not found"):
        resolve(path, overrides_path, str(propeller_dir))


def test_base_pointing_at_nothing_is_rejected(consumer, overrides_path, propeller_dir):
    project = consumer / "sources" / "store-tuned" / "project.yaml"
    project.write_text(project.read_text().replace("base: local:store", "base: local:absent"))
    with pytest.raises(SourceError, match="not found"):
        resolve(consumer / "platforms" / "main" / "pipeline.yaml", overrides_path, str(propeller_dir))


def test_first_matching_source_directory_wins(consumer, overrides_path, propeller_dir):
    """Search order across several `sources:` entries."""
    shadow = consumer / "extra" / "store"
    shadow.mkdir(parents=True)
    (shadow / "project.yaml").write_text("name: store\ndeploy:\n  type: just\n")
    overrides_path.write_text(
        overrides_path.read_text().replace("  - sources/\n", "  - extra/\n  - sources/\n")
    )
    pipeline = resolve(
        consumer / "platforms" / "main" / "pipeline.yaml", overrides_path, str(propeller_dir)
    )
    assert str(_steps(pipeline)["store-one"].source) == str(shadow)


def test_root_level_framework_project_is_reachable_by_name(propeller_dir):
    """`autopilot` sits at the framework root, not under a layer's projects/."""
    from propeller_engine.pipeline.resolve import _discover_projects

    resolved = sources_resolve(
        "propeller:autopilot",
        consumer=[],
        adjacent={},
        framework=_discover_projects(str(propeller_dir)),
        framework_root=propeller_dir.parent,
    )
    assert Path(resolved) == propeller_dir.parent / "autopilot"


def test_deprecated_alias_takes_a_path_from_the_framework_root(propeller_dir):
    resolved = sources_resolve(
        "propeller://autopilot",
        consumer=[],
        adjacent={},
        framework={},
        framework_root=propeller_dir.parent,
    )
    assert Path(resolved) == propeller_dir.parent / "autopilot"


def test_local_scheme_reaches_a_project_beside_the_pipeline(resolved, consumer):
    """The layout CCE uses: one project per pipeline, in projects/ beside it."""
    for name in ("adjacent-implicit", "adjacent-named"):
        expected = consumer / "platforms" / "main" / "projects" / name
        assert str(_steps(resolved)[name].source) == str(expected)


def test_omitted_source_is_rejected(consumer, overrides_path, propeller_dir):
    """Every step names where its project comes from."""
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(path.read_text().replace("        source: local:cache\n", ""))
    with pytest.raises(Exception, match="has no source"):
        resolve(path, overrides_path, str(propeller_dir))


def test_bare_source_is_rejected(consumer, overrides_path, propeller_dir):
    """A reference with no namespace could mean either, so it means neither."""
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(path.read_text().replace("source: local:cache", "source: cache"))
    with pytest.raises(SourceError, match="has no namespace"):
        resolve(path, overrides_path, str(propeller_dir))


def test_the_error_suggests_both_namespaces(consumer, overrides_path, propeller_dir):
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(path.read_text().replace("source: local:cache", "source: cache"))
    with pytest.raises(SourceError) as err:
        resolve(path, overrides_path, str(propeller_dir))
    assert "local:cache" in str(err.value)
    assert "propeller:cache" in str(err.value)


def test_unknown_framework_name_lists_what_is_available(
    consumer, overrides_path, propeller_dir
):
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(path.read_text().replace("source: propeller:smoke-test", "source: propeller:absent"))
    with pytest.raises(SourceError, match="is not a framework project"):
        resolve(path, overrides_path, str(propeller_dir))


def test_declared_sources_are_searched_before_adjacent_projects(
    consumer, overrides_path, propeller_dir
):
    """`local:` searches declared `sources:` first, then projects/ beside the pipeline."""
    shadow = consumer / "sources" / "adjacent-named"
    shadow.mkdir()
    (shadow / "project.yaml").write_text("name: adjacent-named\ndeploy:\n  type: just\n")
    pipeline = resolve(
        consumer / "platforms" / "main" / "pipeline.yaml", overrides_path, str(propeller_dir)
    )
    assert str(_steps(pipeline)["adjacent-named"].source) == str(shadow)


# ── CodeBuild floor/override folding ──────────────────────────────────────────


def _write_store_floor(consumer: Path, block: str) -> None:
    """Give the `store` source a deploy.codebuild floor."""
    proj = consumer / "sources" / "store" / "project.yaml"
    proj.write_text("name: store\ndeploy:\n  type: just\n  codebuild:\n" + block)


def _add_step_codebuild(consumer: Path, block: str) -> None:
    """Attach a per-step codebuild block to the store-two step."""
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(
        path.read_text().replace(
            "      - project: store-two\n        source: local:store\n        target: acct-primary\n",
            "      - project: store-two\n        source: local:store\n        target: acct-primary\n"
            + block,
        )
    )


def test_project_codebuild_lands_on_the_step(consumer, overrides_path, propeller_dir):
    _write_store_floor(
        consumer,
        "    privileged: true\n    compute_type: BUILD_GENERAL1_LARGE\n    min_timeout: 60\n",
    )
    pipeline = resolve(
        consumer / "platforms" / "main" / "pipeline.yaml",
        overrides_path,
        str(propeller_dir),
    )
    assert _steps(pipeline)["store-one"].codebuild == {
        "privileged": True,
        "compute_type": "BUILD_GENERAL1_LARGE",
        "timeout": 60,
    }


def test_per_step_compute_overrides_the_project(
    consumer, overrides_path, propeller_dir
):
    _write_store_floor(consumer, "    compute_type: BUILD_GENERAL1_MEDIUM\n")
    _add_step_codebuild(
        consumer, "        codebuild:\n          compute_type: BUILD_GENERAL1_SMALL\n"
    )
    pipeline = resolve(
        consumer / "platforms" / "main" / "pipeline.yaml",
        overrides_path,
        str(propeller_dir),
    )
    # compute is a plain override: the most-specific value wins, even if smaller.
    assert _steps(pipeline)["store-two"].codebuild == {
        "compute_type": "BUILD_GENERAL1_SMALL"
    }


def test_min_timeout_is_a_floor_the_consumer_cannot_lower(
    consumer, overrides_path, propeller_dir
):
    _write_store_floor(consumer, "    min_timeout: 60\n")
    _add_step_codebuild(consumer, "        codebuild:\n          timeout: 10\n")
    pipeline = resolve(
        consumer / "platforms" / "main" / "pipeline.yaml",
        overrides_path,
        str(propeller_dir),
    )
    # timeout is a floor: the max of min_timeout and the consumer value wins.
    assert _steps(pipeline)["store-two"].codebuild == {"timeout": 60}


def test_consumer_timeout_above_the_floor_wins(
    consumer, overrides_path, propeller_dir
):
    _write_store_floor(consumer, "    min_timeout: 30\n")
    _add_step_codebuild(consumer, "        codebuild:\n          timeout: 90\n")
    pipeline = resolve(
        consumer / "platforms" / "main" / "pipeline.yaml",
        overrides_path,
        str(propeller_dir),
    )
    assert _steps(pipeline)["store-two"].codebuild == {"timeout": 90}


def test_legacy_top_level_timeout_feeds_the_floor_max(
    consumer, overrides_path, propeller_dir
):
    _write_store_floor(consumer, "    min_timeout: 30\n")
    _add_step_codebuild(consumer, "        timeout: 120\n")
    pipeline = resolve(
        consumer / "platforms" / "main" / "pipeline.yaml",
        overrides_path,
        str(propeller_dir),
    )
    assert _steps(pipeline)["store-two"].codebuild == {"timeout": 120}


def test_no_codebuild_config_leaves_the_step_clean(resolved):
    step = _steps(resolved)["cache-one"]
    assert step.codebuild is None
    data = pipeline_to_dict(resolved)
    steps = {s["project"]: s for st in data["stages"] for s in st["steps"]}
    assert "codebuild" not in steps["cache-one"]


def test_step_codebuild_is_serialised_to_the_lock(
    consumer, overrides_path, propeller_dir
):
    _write_store_floor(consumer, "    privileged: true\n")
    pipeline = resolve(
        consumer / "platforms" / "main" / "pipeline.yaml",
        overrides_path,
        str(propeller_dir),
    )
    data = pipeline_to_dict(pipeline)
    steps = {s["project"]: s for st in data["stages"] for s in st["steps"]}
    assert steps["store-one"]["codebuild"] == {"privileged": True}


def _set_pipeline_codebuild(consumer: Path, block: str) -> None:
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(
        path.read_text().replace('version: "1"\n', 'version: "1"\n' + block)
    )


def test_precedence_compute_overrides_timeout_floors(
    consumer, overrides_path, propeller_dir
):
    # project: compute MEDIUM, min_timeout 30
    _write_store_floor(
        consumer, "    compute_type: BUILD_GENERAL1_MEDIUM\n    min_timeout: 30\n"
    )
    # pipeline baseline: compute LARGE, timeout 45
    _set_pipeline_codebuild(
        consumer,
        "codebuild:\n  compute_type: BUILD_GENERAL1_LARGE\n  timeout: 45\n",
    )
    # per-step on store-two: compute XLARGE
    _add_step_codebuild(
        consumer, "        codebuild:\n          compute_type: BUILD_GENERAL1_XLARGE\n"
    )
    pipeline = resolve(
        consumer / "platforms" / "main" / "pipeline.yaml",
        overrides_path,
        str(propeller_dir),
    )
    steps = _steps(pipeline)
    # store-two: step compute wins (most specific); timeout = max(30, 45) = 45.
    assert steps["store-two"].codebuild == {
        "compute_type": "BUILD_GENERAL1_XLARGE",
        "timeout": 45,
    }
    # store-one: no per-step, so pipeline compute beats project; same timeout max.
    assert steps["store-one"].codebuild == {
        "compute_type": "BUILD_GENERAL1_LARGE",
        "timeout": 45,
    }


def test_pipeline_level_codebuild_passes_through_to_the_lock(
    consumer, overrides_path, propeller_dir
):
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(
        path.read_text().replace(
            'version: "1"\n',
            'version: "1"\n'
            "codebuild:\n"
            "  image_repo: 111111111111.dkr.ecr.eu-central-2.amazonaws.com/deploy-runner-image\n"
            "  compute_type: BUILD_GENERAL1_MEDIUM\n",
        )
    )
    pipeline = resolve(path, overrides_path, str(propeller_dir))
    data = pipeline_to_dict(pipeline)
    assert data["codebuild"] == {
        "image_repo": "111111111111.dkr.ecr.eu-central-2.amazonaws.com/deploy-runner-image",
        "compute_type": "BUILD_GENERAL1_MEDIUM",
    }


def test_deploy_runner_image_declares_privileged_and_default_image(
    consumer, overrides_path, propeller_dir
):
    # Point a step at the real framework project and assert its floor is folded.
    path = consumer / "platforms" / "main" / "pipeline.yaml"
    path.write_text(
        path.read_text().replace(
            "source: propeller:smoke-test", "source: propeller:deploy-runner-image", 1
        )
    )
    pipeline = resolve(path, overrides_path, str(propeller_dir))
    assert _steps(pipeline)["framework-smoke"].codebuild == {
        "privileged": True,
        "default_image": True,
    }
