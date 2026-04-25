"""Pipeline validation checks."""

from __future__ import annotations

from pathlib import Path

from ..models import Pipeline


def validate_no_duplicates(pipeline: Pipeline) -> list[str]:
    seen: dict[str, str] = {}
    errors = []
    for stage in pipeline.stages:
        for step in stage.steps:
            if step.project in seen:
                errors.append(
                    f"Duplicate project '{step.project}' "
                    f"in stages '{seen[step.project]}' and '{stage.name}'"
                )
            seen[step.project] = stage.name
    return errors


def validate_depends_on_exist(pipeline: Pipeline) -> list[str]:
    all_projects = {s.project for st in pipeline.stages for s in st.steps}
    errors = []
    for stage in pipeline.stages:
        for step in stage.steps:
            for dep in step.depends_on:
                if dep not in all_projects:
                    errors.append(
                        f"Project '{step.project}' depends on unknown project '{dep}'"
                    )
    return errors


def validate_depends_on_same_stage(pipeline: Pipeline) -> list[str]:
    errors = []
    for stage in pipeline.stages:
        stage_projects = {s.project for s in stage.steps}
        for step in stage.steps:
            for dep in step.depends_on:
                if dep not in stage_projects:
                    errors.append(
                        f"Project '{step.project}' (stage '{stage.name}') "
                        f"depends on '{dep}' which is not in the same stage"
                    )
    return errors


def validate_no_cycles(pipeline: Pipeline) -> list[str]:
    graph: dict[str, list[str]] = {}
    for stage in pipeline.stages:
        for step in stage.steps:
            graph[step.project] = step.depends_on

    visited: set[str] = set()
    in_stack: set[str] = set()
    errors = []

    def dfs(node: str) -> bool:
        visited.add(node)
        in_stack.add(node)
        for neighbor in graph.get(node, []):
            if neighbor in in_stack:
                errors.append(f"Circular dependency: '{node}' -> '{neighbor}'")
                return True
            if neighbor not in visited:
                if dfs(neighbor):
                    return True
        in_stack.discard(node)
        return False

    for node in graph:
        if node not in visited:
            dfs(node)
    return errors


def validate_sources_exist(pipeline: Pipeline) -> list[str]:
    errors = []
    for stage in pipeline.stages:
        for step in stage.steps:
            if step.source and not Path(step.source).is_dir():
                errors.append(
                    f"Project '{step.project}' source '{step.source}' does not exist"
                )
    return errors


def validate_pipeline(pipeline: Pipeline, check_sources: bool = True) -> list[str]:
    errors = []
    errors.extend(validate_no_duplicates(pipeline))
    errors.extend(validate_depends_on_exist(pipeline))
    errors.extend(validate_depends_on_same_stage(pipeline))
    errors.extend(validate_no_cycles(pipeline))
    if check_sources:
        errors.extend(validate_sources_exist(pipeline))
    return errors
