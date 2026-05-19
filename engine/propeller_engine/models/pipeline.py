"""Models for the resolved pipeline definition."""

from __future__ import annotations

from pydantic import BaseModel, Field


class ProjectInput(BaseModel):
    """Resolved input: SSM key + optional field (for JSON blob) + variable name."""

    key: str
    var: str
    field: str | None = None


class ProjectOutput(BaseModel):
    """Resolved output: SSM key + optional field (for JSON blob) + terraform/script output name."""

    key: str
    ref: str
    field: str | None = None


class Step(BaseModel):
    project: str
    source: str | None = None
    target: str | None = None
    depends_on: list[str] = Field(default_factory=list)
    inputs: list[dict | ProjectInput] = Field(default_factory=list)
    outputs: list[dict | ProjectOutput] = Field(default_factory=list)


class Stage(BaseModel):
    name: str
    steps: list[Step]


class Pipeline(BaseModel):
    version: str
    namespace: str | None = None
    propeller_version: str | None = None
    resolved_at: str | None = None
    stages: list[Stage]
