"""Script deploy runner — delegates to just recipes."""

from __future__ import annotations

import json

from .runner import DeployRunner, log, run_cmd, write_outputs_file


class ScriptRunner(DeployRunner):
    def _just(self, recipe: str) -> int:
        cmd = ["just", recipe]
        for var_name, value in self.inputs.items():
            cmd.append(f"{var_name}={value}")
        return run_cmd(cmd, cwd=self.project_dir)

    def init(self) -> int:
        return self._just("init")

    def plan(self) -> int:
        return self._just("plan")

    def apply(self) -> int:
        rc = self._just("apply")
        if rc != 0:
            return rc
        self._read_outputs()
        return 0

    def destroy(self) -> int:
        return self._just("destroy")

    def outputs(self) -> int:
        return self._just("outputs")

    def _read_outputs(self) -> None:
        output_defs = self.project.get("outputs", [])
        if not output_defs:
            write_outputs_file({}, self.project_dir)
            return

        outputs_path = self.project_dir / ".propeller-outputs.json"
        if not outputs_path.exists():
            log("Warning: script did not produce .propeller-outputs.json")
            write_outputs_file({}, self.project_dir)
            return

        all_outputs = json.loads(outputs_path.read_text())
        outputs = {}
        for out_def in output_defs:
            ref = out_def["ref"]
            if ref in all_outputs:
                outputs[ref] = str(all_outputs[ref])
                log(f"Output: {ref} → {outputs[ref]}")
            else:
                log(f"Warning: output '{ref}' not found in script outputs")

        write_outputs_file(outputs, self.project_dir)
