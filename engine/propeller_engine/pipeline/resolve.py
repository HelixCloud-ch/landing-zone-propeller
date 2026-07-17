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


def _discover_projects(propeller_dir: str) -> dict[str, dict]:
    """Return a map of project_name → {path, project_yaml}."""
    projects_root = Path(propeller_dir) / "projects"
    result: dict[str, dict] = {}
    if not projects_root.is_dir():
        return result
    for project_yaml in projects_root.rglob("project.yaml"):
        data = yaml.safe_load(project_yaml.read_text())
        name = data.get("name")
        if name:
            result[name] = {"path": str(project_yaml.parent), "yaml": data}
    return result


def _set_default_sources(
    pipeline: Pipeline, project_index: dict[str, dict], propeller_dir: str
) -> None:
    propeller_root = str(Path(propeller_dir).parent)
    for stage in pipeline.stages:
        for step in stage.steps:
            if step.source is None:
                # No source - look up by project name
                entry = project_index.get(step.project)
                step.source = (
                    entry["path"]
                    if entry
                    else f"{propeller_dir}/projects/{step.project}"
                )
            elif step.source.startswith("propeller://"):
                # Explicit framework path - resolve relative to framework root
                rel_path = step.source.removeprefix("propeller://")
                step.source = str(Path(propeller_root) / rel_path)
            elif step.source in project_index:
                # Source is a project name reference - resolve to path
                step.source = project_index[step.source]["path"]
            # else: source is already a path, leave as-is


def _load_project_yaml_for_step(step: Step, project_index: dict[str, dict]) -> dict:
    """Load project.yaml for a step, looking up by project name first then by source path."""
    entry = project_index.get(step.project)
    if entry:
        return entry["yaml"]
    if step.source:
        path = Path(step.source) / "project.yaml"
        if path.exists():
            return yaml.safe_load(path.read_text())
    return {}


def _propeller_tags_for_step(
    step: Step, pipeline: Pipeline, project_yaml: dict
) -> dict[str, str]:
    """Compute framework-managed tags for a step.

    Tags are emitted only when their source value is set; missing values
    produce no tag (rather than an empty-string tag).
    """
    tags: dict[str, str] = {}
    if pipeline.namespace:
        tags["propeller:pipeline"] = pipeline.namespace
    tags["propeller:project"] = step.project

    deploy_type = (project_yaml.get("deploy") or {}).get("type")
    if deploy_type:
        tags["propeller:deploy-type"] = deploy_type

    metadata = project_yaml.get("metadata") or {}
    cost_center = metadata.get("cost-center")
    if cost_center:
        tags["propeller:cost-center"] = str(cost_center)
    if metadata.get("framework-required") is True:
        tags["propeller:framework-required"] = "true"

    return tags


def _attach_propeller_tags(pipeline: Pipeline, project_index: dict[str, dict]) -> None:
    for stage in pipeline.stages:
        for step in stage.steps:
            project_yaml = _load_project_yaml_for_step(step, project_index)
            step.propeller_tags = _propeller_tags_for_step(step, pipeline, project_yaml)
            # Inject sleep config from project.yaml into the step for runtime use
            sleep_block = project_yaml.get("sleep")
            if sleep_block:
                step.sleep_config = sleep_block


SSM_PREFIX = "/propeller"


def _expand_input(
    inp: dict, namespace: str | None, step_project: str | None = None
) -> dict:
    """Expand shorthand input format to resolved format.

    Inputs always reference another project's output:
    - name: "other-project.field_name" → blob read from /propeller/{namespace}/{project}, field=field_name
    - name: "/absolute.path.here" → individual parameter read
    - name: "@namespace/project.field" → cross-pipeline blob read

    Example: {name: "control-tower.org_id", var: "org_id"} with namespace "landing-zone"
    Resolved: {key: "/propeller/landing-zone/control-tower", field: "org_id", var: "org_id"}

    Cross-pipeline: {name: "@landing-zone/workload-parameters.tgw_id", var: "tgw_id"}
    Resolved: {key: "/propeller/landing-zone/workload-parameters", field: "tgw_id", var: "tgw_id"}
    """
    if "name" in inp and "key" not in inp:
        name = inp["name"]
        if name.startswith("@"):
            # Cross-pipeline blob reference: @namespace/project.field
            rest = name[1:]
            if "." not in rest:
                raise ResolveError(
                    f"Cross-pipeline input '{name}' must include a field (e.g. @ns/project.field)"
                )
            path_part, field = rest.rsplit(".", 1)
            return {
                "key": f"{SSM_PREFIX}/{path_part}",
                "field": field,
                "var": inp.get("var", field),
            }
        elif name.startswith("/"):
            # Absolute SSM parameter: /accounts.network.id
            path = name[1:].replace(".", "/")
            return {
                "key": f"{SSM_PREFIX}/{path}",
                "var": inp.get("var", name.rsplit(".", 1)[-1]),
            }
        else:
            # Intra-pipeline blob reference: project.field
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


def _expand_output(
    out: dict, namespace: str | None, step_project: str | None = None
) -> dict:
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
                "ref": out.get("var", name.rsplit(".", 1)[-1]),
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
                "ref": out.get("var", name),
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
                    expanded_inputs.append(
                        ProjectInput(**_expand_input(raw, namespace, step.project))
                    )
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
    version: str | None = None,
) -> Pipeline:
    pipeline = copy.deepcopy(load_base_pipeline(base_path))

    if overrides_path:
        config = load_overrides(overrides_path)
        _apply_removals(pipeline, config.pipeline)
        _apply_overrides(pipeline, config.pipeline)
        _apply_additions(pipeline, config.pipeline)
        _apply_stage_order(pipeline, config.pipeline)
        targets = config.pipeline.targets
        consumer_tags = {**dict(pipeline.tags), **dict(config.tags or {})}
    else:
        targets = {}
        consumer_tags = dict(pipeline.tags)

    # The version is supplied by the consumer tooling (read from the version
    # pin file and passed via --version). Defaults to "dev" for framework-local
    # runs with no version.
    propeller_version = version or "dev"

    project_index = _discover_projects(propeller_dir)
    # Also discover consumer projects adjacent to the pipeline file
    consumer_projects_dir = base_path.parent / "projects"
    if consumer_projects_dir.is_dir():
        for project_yaml in consumer_projects_dir.rglob("project.yaml"):
            data = yaml.safe_load(project_yaml.read_text())
            name = data.get("name")
            if name and name not in project_index:
                project_index[name] = {"path": str(project_yaml.parent), "yaml": data}
    _set_default_sources(pipeline, project_index, propeller_dir)
    _expand_step_io(pipeline)
    _apply_targets(pipeline, targets)

    pipeline.propeller_version = propeller_version
    pipeline.consumer_tags = consumer_tags
    _attach_propeller_tags(pipeline, project_index)
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
    if step.propeller_tags:
        d["propeller_tags"] = dict(step.propeller_tags)
    if step.timeout:
        d["timeout"] = step.timeout
    if step.runner:
        d["runner"] = step.runner
    if step.sleep:
        d["sleep"] = step.sleep
    if step.sleep_config:
        d["sleep_config"] = step.sleep_config
    if step.approval:
        d["approval"] = step.approval
    return d


def pipeline_to_dict(pipeline: Pipeline) -> dict:
    data: dict = {
        "version": pipeline.version,
        "namespace": pipeline.namespace,
        "propeller_version": pipeline.propeller_version,
        "resolved_at": pipeline.resolved_at,
        "stages": [],
    }
    if pipeline.consumer_tags:
        data["consumer_tags"] = dict(pipeline.consumer_tags)
    for stage in pipeline.stages:
        data["stages"].append(
            {
                "name": stage.name,
                "steps": [_step_to_dict(s) for s in stage.steps],
            }
        )
    return data
