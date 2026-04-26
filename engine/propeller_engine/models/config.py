from __future__ import annotations

from pydantic import BaseModel, Field


class StepOverride(BaseModel):
    project: str
    source: str | None = None


class Removal(BaseModel):
    project: str


class PipelineOverrides(BaseModel):
    targets: dict[str, str] = Field(default_factory=dict)
    overrides: list[StepOverride] = Field(default_factory=list)
    additions: list[dict] = Field(default_factory=list)
    removals: list[Removal] = Field(default_factory=list)
    stage_order: list[str] | None = None


class PropellerConfig(BaseModel):
    propeller: dict
    pipeline: PipelineOverrides = Field(default_factory=PipelineOverrides)
