"""Resolve a base pipeline with overrides into a final pipeline."""

from __future__ import annotations

import copy
from datetime import datetime, timezone
from pathlib import Path

import yaml

from . import sources
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
    """Return a map of project_name → {path, yaml} for every framework project.

    Covers both layers' projects/ directories plus any directory at the framework
    root declaring a project.yaml, so a root-level project such as autopilot is
    reachable by name. A framework project name is a global identifier: two layers
    declaring the same name is an error, since `propeller:<name>` would otherwise
    mean different things depending on which layer the pipeline was resolved against.
    """
    root = Path(propeller_dir).parent
    result: dict[str, dict] = {}
    seen: dict[str, str] = {}

    candidates = sorted(root.glob("*/project.yaml"))
    for layer in sorted(root.glob("*/projects")):
        candidates.extend(sorted(layer.glob("*/project.yaml")))

    for project_yaml in candidates:
        data = yaml.safe_load(project_yaml.read_text()) or {}
        name = data.get("name")
        if not name:
            raise ResolveError(
                f"{project_yaml} declares no name, so nothing can reference it"
            )
        path = str(project_yaml.parent)
        if name in seen and seen[name] != path:
            raise ResolveError(
                f"framework project name '{name}' is declared twice:\n"
                f"  {seen[name]}\n  {path}\n"
                "Framework project names must be unique across layers."
            )
        seen[name] = path
        result[name] = {"path": path, "yaml": data}
    return result


def _set_overlays(
    step: Step, overlay_root: Path | None, defaults: list[str] | None = None
) -> None:
    """Expand each declared overlay pattern and keep the ones that exist.

    Patterns are resolved here so the lock file lists the directories that will
    actually be applied, leaving the bundler to copy. A pattern naming a directory
    that is absent is normal: most instances have no overlay.
    """
    patterns = step.overlays or defaults or []
    if not patterns:
        return
    root = overlay_root or Path.cwd()
    resolved = []
    for pattern in patterns:
        path = root / pattern.replace("${project}", step.project)
        if path.is_dir():
            resolved.append(str(path))
    step.overlays = resolved


def _set_default_sources(
    pipeline: Pipeline,
    framework: dict[str, dict],
    propeller_dir: str,
    consumer_dirs: list[Path] | None = None,
    adjacent: dict[str, dict] | None = None,
    overlay_root: Path | None = None,
) -> None:
    consumer = consumer_dirs or []
    adjacent = adjacent or {}
    framework_root = Path(propeller_dir).parent
    for stage in pipeline.stages:
        for step in stage.steps:
            if step.source is None:
                raise ResolveError(
                    f"step '{step.project}' has no source. Write "
                    f"'local:{step.project}' for a project in this repo, or "
                    f"'propeller:{step.project}' for a framework project."
                )
            step.source = sources.resolve(
                step.source,
                consumer=consumer,
                adjacent=adjacent,
                framework=framework,
                framework_root=framework_root,
            )
            _set_base(step, consumer, adjacent, framework, framework_root)
            _set_overlays(step, overlay_root, pipeline.overlays)


def _set_base(
    step: Step,
    consumer: list[Path],
    adjacent: dict[str, dict],
    framework: dict[str, dict],
    framework_root: Path,
) -> None:
    """Resolve the source project's `base:` to a path, for the bundler to layer.

    Resolution happens here rather than in the bundler so that every reference is
    resolved in one place and the lock file records the outcome.
    """
    project_yaml = Path(step.source) / "project.yaml" if step.source else None
    if project_yaml is None or not project_yaml.is_file():
        return
    declared = (yaml.safe_load(project_yaml.read_text()) or {}).get("base")
    if not declared:
        return
    resolved = sources.resolve(
        declared,
        consumer=consumer,
        adjacent=adjacent,
        framework=framework,
        framework_root=framework_root,
    )
    if not Path(resolved).is_dir():
        raise ResolveError(
            f"project '{step.project}' declares base '{declared}' which does not exist"
        )
    step.base = resolved


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


def _max_timeout(*values: int | None) -> int | None:
    present = [v for v in values if v is not None]
    return max(present) if present else None


def _fold_codebuild(step: Step, project_yaml: dict, pipeline_cb: dict | None) -> None:
    """Resolve the effective CodeBuild config into step.codebuild.

    - compute_type: most-specific wins, step > pipeline > project.
    - timeout: max of the project's min_timeout and any consumer value
      (pipeline, per-step, or the legacy top-level step.timeout).
    - privileged: ORed. default_image: the project's.

    image/image_repo stay pipeline-level (composed at build start), not folded here.
    """
    project_cb = (project_yaml.get("deploy") or {}).get("codebuild") or {}
    pipeline_cb = pipeline_cb or {}
    step_cb = dict(step.codebuild or {})

    folded: dict = {}
    if project_cb.get("privileged") or step_cb.get("privileged"):
        folded["privileged"] = True
    if project_cb.get("default_image"):
        folded["default_image"] = True

    compute = (
        step_cb.get("compute_type")
        or pipeline_cb.get("compute_type")
        or project_cb.get("compute_type")
    )
    if compute:
        folded["compute_type"] = compute

    timeout = _max_timeout(
        project_cb.get("min_timeout"),
        pipeline_cb.get("timeout"),
        step_cb.get("timeout"),
        step.timeout,
    )
    if timeout is not None:
        folded["timeout"] = timeout

    step.codebuild = folded or None


def _attach_propeller_tags(pipeline: Pipeline, project_index: dict[str, dict]) -> None:
    for stage in pipeline.stages:
        for step in stage.steps:
            project_yaml = _load_project_yaml_for_step(step, project_index)
            step.propeller_tags = _propeller_tags_for_step(step, pipeline, project_yaml)
            # Inject sleep config from project.yaml into the step for runtime use
            sleep_block = project_yaml.get("sleep")
            if sleep_block:
                step.sleep_config = sleep_block
            # Resolve project floor + pipeline baseline + per-step override
            _fold_codebuild(step, project_yaml, pipeline.codebuild)


SSM_PREFIX = "/propeller"


def _expand_input(
    inp: dict, namespace: str | None, step_project: str | None = None
) -> dict:
    """Expand shorthand input format to resolved format.

    Inputs reference another project's output, or carry a literal:
    - name: "other-project.field_name" → blob read from /propeller/{namespace}/{project}, field=field_name
    - name: "/absolute.path.here" → individual parameter read
    - name: "@namespace/project.field" → cross-pipeline blob read
    - literal: "text" → passed through with no read

    Example: {name: "control-tower.org_id", var: "org_id"} with namespace "landing-zone"
    Resolved: {key: "/propeller/landing-zone/control-tower", field: "org_id", var: "org_id"}

    Cross-pipeline: {name: "@landing-zone/workload-parameters.tgw_id", var: "tgw_id"}
    Resolved: {key: "/propeller/landing-zone/workload-parameters", field: "tgw_id", var: "tgw_id"}

    Literal: {literal: "1.2.3", var: "chart_version"}
    Resolved: {literal: "1.2.3", var: "chart_version"}
    """
    if "literal" in inp and "name" not in inp:
        # Literal: no SSM read at deploy time.
        result = {"var": inp["var"], "literal": inp["literal"]}
        if inp.get("expr"):
            result["expr"] = inp["expr"]
        return result
    if "name" in inp and "key" not in inp:
        name = inp["name"]
        jq = inp.get("expr")  # Preserve expr transform if present
        if name.startswith("@"):
            # Cross-pipeline blob reference: @namespace/project.field
            rest = name[1:]
            if "." not in rest:
                raise ResolveError(
                    f"Cross-pipeline input '{name}' must include a field (e.g. @ns/project.field)"
                )
            path_part, field = rest.rsplit(".", 1)
            result = {
                "key": f"{SSM_PREFIX}/{path_part}",
                "field": field,
                "var": inp.get("var", field),
            }
        elif name.startswith("/"):
            # Absolute SSM parameter: /accounts.network.id
            path = name[1:].replace(".", "/")
            result = {
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
            result = {
                "key": f"{SSM_PREFIX}/{path}",
                "field": field,
                "var": inp.get("var", field),
            }
        if jq:
            result["expr"] = jq
        return result
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
        consumer_dirs = sources.consumer_dirs(overrides_path, config.sources)
    else:
        targets = {}
        consumer_tags = dict(pipeline.tags)
        consumer_dirs = []

    # The version is supplied by the consumer tooling (read from the version
    # pin file and passed via --version). Defaults to "dev" for framework-local
    # runs with no version.
    propeller_version = version or "dev"

    project_index = _discover_projects(propeller_dir)
    # Also discover consumer projects adjacent to the pipeline file
    consumer_projects_dir = base_path.parent / "projects"
    adjacent: dict[str, dict] = {}
    if consumer_projects_dir.is_dir():
        for project_yaml in consumer_projects_dir.rglob("project.yaml"):
            data = yaml.safe_load(project_yaml.read_text()) or {}
            name = data.get("name")
            if not name:
                raise ResolveError(
                    f"{project_yaml} declares no name, so nothing can reference it"
                )
            adjacent[name] = {"path": str(project_yaml.parent), "yaml": data}
    _set_default_sources(
        pipeline,
        project_index,
        propeller_dir,
        consumer_dirs,
        adjacent,
        overlay_root=overrides_path.parent if overrides_path else base_path.parent,
    )
    _expand_step_io(pipeline)
    _apply_targets(pipeline, targets)

    pipeline.propeller_version = propeller_version
    pipeline.consumer_tags = consumer_tags
    _attach_propeller_tags(pipeline, project_index)
    pipeline.resolved_at = datetime.now(timezone.utc).isoformat()
    return pipeline


def _step_to_dict(step: Step) -> dict:
    d: dict = {"project": step.project, "source": step.source}
    if step.base:
        d["base"] = step.base
    if step.overlays:
        d["overlays"] = list(step.overlays)
    if step.target:
        d["target"] = step.target
    if step.depends_on:
        d["depends_on"] = step.depends_on
    if step.inputs:
        d["inputs"] = [i.model_dump(exclude_none=True) for i in step.inputs]
    if step.outputs:
        d["outputs"] = [o.model_dump(exclude_none=True) for o in step.outputs]
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
    if step.codebuild:
        d["codebuild"] = dict(step.codebuild)
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
    if pipeline.sleep_presets:
        data["sleep_presets"] = dict(pipeline.sleep_presets)
    if pipeline.codebuild:
        data["codebuild"] = dict(pipeline.codebuild)
    for stage in pipeline.stages:
        stage_dict: dict = {
            "name": stage.name,
            "steps": [_step_to_dict(s) for s in stage.steps],
        }
        if not stage.barrier:
            stage_dict["barrier"] = False
        data["stages"].append(stage_dict)
    return data
