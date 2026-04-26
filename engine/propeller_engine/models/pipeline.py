"""Models for the resolved pipeline definition."""

from __future__ import annotations

from pydantic import BaseModel, Field


class ProjectInput(BaseModel):
    """Resolved input: full SSM key + variable name."""

    key: str
    var: str


class ProjectOutput(BaseModel):
    """Resolved output: full SSM key + terraform/script output name."""

    key: str
    ref: str


class Step(BaseModel):
    project: str
    source: str | None = None
    target: str | None = None
    depends_on: list[str] = Field(default_factory=list)
    inputs: list[ProjectInput] = Field(default_factory=list)
    outputs: list[ProjectOutput] = Field(default_factory=list)


class Stage(BaseModel):
    name: str
    steps: list[Step]


class Pipeline(BaseModel):
    version: str
    propeller_version: str | None = None
    resolved_at: str | None = None
    stages: list[Stage]
