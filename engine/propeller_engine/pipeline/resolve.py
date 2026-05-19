"""Resolve a base pipeline with overrides into a final pipeline."""

from __future__ import annotations

import copy
from datetime import datetime, timezone
from pathlib import Path

import yaml

from ..models import (
    Pipeline,
    PipelineOverrides,
    ProjectInput,
    ProjectOutput,
    PropellerConfig,
    Stage,
    Step,
)


class ResolveError(Exception):
    pass


def load_base_pipeline(path: Path) -> Pipeline:
    return Pipeline(**yaml.safe_load(path.read_text()))


def load_overrides(path: Path) -> PropellerConfig:
    return PropellerConfig(**yaml.safe_load(path.read_text()))


def _apply_removals(pipeline: Pipeline, overrides: PipelineOverrides) -> None:
    removed = {r.project for r in overrides.removals}
    if not removed:
        return
    for stage in pipeline.stages:
        stage.steps = [s for s in stage.steps if s.project not in removed]
        for step in stage.steps:
            step.depends_on = [d for d in step.depends_on if d not in removed]
    pipeline.stages = [s for s in pipeline.stages if s.steps]


def _apply_overrides(pipeline: Pipeline, overrides: PipelineOverrides) -> None:
    override_map = {o.project: o for o in overrides.overrides}
    if not override_map:
        return
    for stage in pipeline.stages:
        for step in stage.steps:
            if step.project in override_map:
                ov = override_map[step.project]
                if ov.source:
                    step.source = ov.source


def _apply_additions(pipeline: Pipeline, overrides: PipelineOverrides) -> None:
    for addition in overrides.additions:
        stage_name = addition.get("stage")
        if not stage_name:
            raise ResolveError("Addition missing 'stage' field")

        if "after" in addition:
            after_name = addition["after"]
            idx = next(
                (i for i, s in enumerate(pipeline.stages) if s.name == after_name),
                None,
            )
            if idx is None:
                raise ResolveError(
                    f"Cannot insert stage '{stage_name}' after unknown stage '{after_name}'"
                )
            new_steps = [Step(**s) for s in addition.get("steps", [])]
            pipeline.stages.insert(idx + 1, Stage(name=stage_name, steps=new_steps))

        elif "step" in addition:
            target = next((s for s in pipeline.stages if s.name == stage_name), None)
            if target is None:
                raise ResolveError(f"Cannot add step to unknown stage '{stage_name}'")
            target.steps.append(Step(**addition["step"]))


def _apply_stage_order(pipeline: Pipeline, overrides: PipelineOverrides) -> None:
    if overrides.stage_order is None:
        return
    stage_map = {s.name: s for s in pipeline.stages}
    existing = set(stage_map.keys())
    requested = set(overrides.stage_order)

    missing = existing - requested
    if missing:
        raise ResolveError(f"stage_order is missing stages: {missing}")
    unknown = requested - existing
    if unknown:
        raise ResolveError(f"stage_order references unknown stages: {unknown}")

    pipeline.stages = [stage_map[name] for name in overrides.stage_order]


def _discover_projects(propeller_dir: str) -> dict[str, str]:
    projects_root = Path(propeller_dir) / "projects"
    result = {}
    if not projects_root.is_dir():
        return result
    for project_yaml in projects_root.rglob("project.yaml"):
        data = yaml.safe_load(project_yaml.read_text())
        name = data.get("name")
        if name:
            result[name] = str(project_yaml.parent)
    return result


def _set_default_sources(pipeline: Pipeline, propeller_dir: str) -> None:
    project_paths = _discover_projects(propeller_dir)
    for stage in pipeline.stages:
        for step in stage.steps:
            if step.source is None:
                step.source = project_paths.get(
                    step.project, f"{propeller_dir}/projects/{step.project}"
                )


SSM_PREFIX = "/propeller"


def _expand_input(inp: dict, namespace: str | None, step_project: str | None = None) -> dict:
    """Expand shorthand input format to resolved format.

    Inputs always reference another project's output:
    - name: "other-project.field_name" → blob read from /propeller/{namespace}/{project}, field=field_name
    - name: "/absolute.path.here" → individual parameter read

    Example: {name: "control-tower.org_id", var: "org_id"} with namespace "landing-zone"
    Resolved: {key: "/propeller/landing-zone/control-tower", field: "org_id", var: "org_id"}
    """
    if "name" in inp and "key" not in inp:
        name = inp["name"]
        if name.startswith("/"):
            # Absolute path → individual parameter
            path = name[1:].replace(".", "/")
            return {
                "key": f"{SSM_PREFIX}/{path}",
                "var": inp.get("var", name.rsplit(".", 1)[-1]),
            }
        else:
            # project.field → blob read
            parts = name.split(".", 1)
            if len(parts) == 2:
                project_name, field = parts
            else:
                project_name, field = name, name
            if namespace:
                path = f"{namespace}/{project_name}"
            else:
                path = project_name
            return {
                "key": f"{SSM_PREFIX}/{path}",
                "field": field,
                "var": inp.get("var", field),
            }
    return inp  # Already in resolved format


def _expand_output(out: dict, namespace: str | None, step_project: str | None = None) -> dict:
    """Expand shorthand output format to resolved format.

    Outputs:
    - Bare name (no dots, no /): blob output → stored in project's JSON blob
    - / prefix: individual parameter

    Example: {name: "org_id", var: "org_id"} with namespace "landing-zone", project "control-tower"
    Resolved: {key: "/propeller/landing-zone/control-tower", field: "org_id", ref: "org_id"}

    Absolute: {name: "/accounts.backup-admin.id", var: "account_id"}
    Resolved: {key: "/propeller/accounts/backup-admin/id", ref: "account_id"}
    """
    if "name" in out and "key" not in out:
        name = out["name"]
        if name.startswith("/"):
            # Absolute → individual parameter
            path = name[1:].replace(".", "/")
            return {
                "key": f"{SSM_PREFIX}/{path}",
                "ref": out["var"],
            }
        else:
            # Bare name → blob output
            if namespace and step_project:
                path = f"{namespace}/{step_project}"
            elif step_project:
                path = step_project
            else:
                path = name.replace(".", "/")
            return {
                "key": f"{SSM_PREFIX}/{path}",
                "field": name,
                "ref": out["var"],
            }
    return out  # Already in resolved format


def _expand_step_io(pipeline: Pipeline) -> None:
    """Expand shorthand inputs/outputs on pipeline steps to resolved format."""
    namespace = pipeline.namespace
    for stage in pipeline.stages:
        for step in stage.steps:
            if step.inputs:
                expanded_inputs = []
                for i in step.inputs:
                    raw = i.model_dump() if hasattr(i, "model_dump") else i
                    expanded_inputs.append(ProjectInput(**_expand_input(raw, namespace, step.project)))
                step.inputs = expanded_inputs
            if step.outputs:
                expanded_outputs = []
                for o in step.outputs:
                    raw = o.model_dump() if hasattr(o, "model_dump") else o
                    expanded_outputs.append(
                        ProjectOutput(**_expand_output(raw, namespace, step.project))
                    )
                step.outputs = expanded_outputs


def _apply_targets(pipeline: Pipeline, targets: dict[str, str]) -> None:
    for stage in pipeline.stages:
        for step in stage.steps:
            if step.project in targets:
                step.target = targets[step.project]


def resolve(
    base_path: Path,
    overrides_path: Path | None,
    propeller_dir: str = ".propeller",
) -> Pipeline:
    pipeline = copy.deepcopy(load_base_pipeline(base_path))

    if overrides_path:
        config = load_overrides(overrides_path)
        _apply_removals(pipeline, config.pipeline)
        _apply_overrides(pipeline, config.pipeline)
        _apply_additions(pipeline, config.pipeline)
        _apply_stage_order(pipeline, config.pipeline)
        propeller_version = config.propeller.get("version", "unknown")
        targets = config.pipeline.targets
    else:
        propeller_version = "dev"
        targets = {}

    _set_default_sources(pipeline, propeller_dir)
    _expand_step_io(pipeline)
    _apply_targets(pipeline, targets)

    pipeline.propeller_version = propeller_version
    pipeline.resolved_at = datetime.now(timezone.utc).isoformat()
    return pipeline


def _step_to_dict(step: Step) -> dict:
    d: dict = {"project": step.project, "source": step.source}
    if step.target:
        d["target"] = step.target
    if step.depends_on:
        d["depends_on"] = step.depends_on
    if step.inputs:
        inputs = []
        for i in step.inputs:
            entry = {"key": i.key, "var": i.var}
            if i.field:
                entry["field"] = i.field
            inputs.append(entry)
        d["inputs"] = inputs
    if step.outputs:
        outputs = []
        for o in step.outputs:
            entry = {"key": o.key, "ref": o.ref}
            if o.field:
                entry["field"] = o.field
            outputs.append(entry)
        d["outputs"] = outputs
    return d


def pipeline_to_dict(pipeline: Pipeline) -> dict:
    data: dict = {
        "version": pipeline.version,
        "namespace": pipeline.namespace,
        "propeller_version": pipeline.propeller_version,
        "resolved_at": pipeline.resolved_at,
        "stages": [],
    }
    for stage in pipeline.stages:
        data["stages"].append(
            {
                "name": stage.name,
                "steps": [_step_to_dict(s) for s in stage.steps],
            }
        )
    return data
