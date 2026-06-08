"""Models for `propeller.overrides.yaml` (the consumer-side config file)."""

from __future__ import annotations

from pydantic import BaseModel, Field


class StepOverride(BaseModel):
    """Replace a step's project source with a consumer-side path."""

    project: str
    source: str | None = None


class Removal(BaseModel):
    """Drop a project from the pipeline."""

    project: str


class PipelineOverrides(BaseModel):
    """Pipeline-level customizations applied on top of the base pipeline."""

    targets: dict[str, str] = Field(default_factory=dict)
    overrides: list[StepOverride] = Field(default_factory=list)
    additions: list[dict] = Field(default_factory=list)
    removals: list[Removal] = Field(default_factory=list)
    stage_order: list[str] | None = None


class PropellerConfig(BaseModel):
    """Top-level config schema for `propeller.overrides.yaml`.

    Sections:
      - `tags`: pipeline-wide tags applied to every project's resources.
      - `pipeline`: optional pipeline-level overrides; defaults to empty.

    The framework version pin lives in the version file read by the consumer
    tooling, not here; the engine receives it via `--version`.
    """

    propeller: dict = Field(default_factory=dict)
    pipeline: PipelineOverrides | None = Field(default_factory=PipelineOverrides)
    tags: dict[str, str] = Field(default_factory=dict)

    def model_post_init(self, __context) -> None:
        # `pipeline: {}` deserializes to None with pydantic's union handling;
        # normalize back to an empty overrides instance so callers can use it
        # without a None check.
        if self.pipeline is None:
            self.pipeline = PipelineOverrides()
