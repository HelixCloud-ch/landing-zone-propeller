"""Script deploy runner — delegates to just recipes."""

from __future__ import annotations

from .runner import DeployRunner, run_cmd


class ScriptRunner(DeployRunner):
    def _just(self, recipe: str) -> int:
        cmd = ["just", recipe]
        return run_cmd(cmd, cwd=self.project_dir)

    def init(self) -> int:
        return self._just("init")

    def plan(self) -> int:
        return self._just("plan")

    def apply(self) -> int:
        rc = self._just("apply")
        if rc != 0:
            return rc
        # The project's justfile apply recipe writes .propeller-outputs.json.
        return 0

    def destroy(self) -> int:
        return self._just("destroy")

    def outputs(self) -> int:
        return self._just("outputs")
