"""Models for the resolved pipeline definition."""

from __future__ import annotations

from pydantic import BaseModel, Field, model_validator


class ProjectInput(BaseModel):
    """Resolved input: either an SSM read or a literal, bound to a variable.

    `key` reads a parameter, optionally taking `field` from a JSON blob.
    `literal` carries a value that needs no read, and travels in the bundle in
    cleartext.
    """

    var: str
    key: str | None = None
    literal: str | None = None
    field: str | None = None
    expr: str | None = None

    @model_validator(mode="after")
    def _one_source(self) -> ProjectInput:
        if (self.key is None) == (self.literal is None):
            raise ValueError(
                f"input '{self.var}' must set exactly one of key or literal"
            )
        return self


class ProjectOutput(BaseModel):
    """Resolved output: SSM key + optional field (for JSON blob) + terraform/script output name."""

    key: str
    ref: str
    field: str | None = None


class Step(BaseModel):
    project: str
    source: str | None = None
    base: str | None = None
    # Path patterns; resolved to existing directories, applied in order after
    # the source.
    overlays: list[str] = Field(default_factory=list)
    target: str | None = None
    depends_on: list[str] = Field(default_factory=list)
    inputs: list[dict | ProjectInput] = Field(default_factory=list)
    outputs: list[dict | ProjectOutput] = Field(default_factory=list)
    propeller_tags: dict[str, str] = Field(default_factory=dict)
    timeout: int | None = None
    runner: str | None = None
    sleep: bool = False
    sleep_config: dict | None = None
    approval: str | None = None

class Stage(BaseModel):
    name: str
    steps: list[Step]
    barrier: bool = True


class Pipeline(BaseModel):
    version: str
    # Default overlay patterns for every step, letting a pipeline state where
    # consumers may overlay its projects without repeating the pattern on each
    # step. A step declaring its own replaces these.
    overlays: list[str] = Field(default_factory=list)
    namespace: str | None = None
    propeller_version: str | None = None
    resolved_at: str | None = None
    stages: list[Stage]
    tags: dict[str, str] = Field(default_factory=dict)
    consumer_tags: dict[str, str] = Field(default_factory=dict)
    sleep_presets: dict[str, dict[str, str]] = Field(default_factory=dict)
