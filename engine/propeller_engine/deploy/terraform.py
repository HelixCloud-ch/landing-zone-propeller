"""Terraform deploy runner."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from .runner import DeployRunner, log, run_cmd, substitute_env, write_outputs_file


class TerraformRunner(DeployRunner):
    @property
    def tf_dir(self) -> Path:
        return self.project_dir / "terraform"

    def _var_args(self) -> list[str]:
        args = []
        if self.config:
            args.extend(["-var-file", self.config])
        for var_name, value in self.inputs.items():
            args.extend(["-var", f"{var_name}={value}"])
        return args

    def init(self) -> int:
        backend = self.project.get("deploy", {}).get("backend", {})
        cmd = ["terraform", "init"]
        for key, value in backend.items():
            cmd.append(f"-backend-config={key}={substitute_env(str(value))}")
        return run_cmd(cmd, cwd=self.tf_dir)

    def plan(self) -> int:
        cmd = ["terraform", "plan", "-out=tfplan"] + self._var_args()
        return run_cmd(cmd, cwd=self.tf_dir)

    def apply(self) -> int:
        rc = run_cmd(["terraform", "apply", "tfplan"], cwd=self.tf_dir)
        if rc != 0:
            return rc
        self._write_outputs()
        return 0

    def destroy(self) -> int:
        cmd = ["terraform", "destroy", "-auto-approve"] + self._var_args()
        return run_cmd(cmd, cwd=self.tf_dir)

    def outputs(self) -> int:
        return run_cmd(["terraform", "output", "-json"], cwd=self.tf_dir)

    def _write_outputs(self) -> None:
        output_defs = self.project.get("outputs", [])
        if not output_defs:
            write_outputs_file({}, self.project_dir)
            return

        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=self.tf_dir,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            log(f"Warning: terraform output failed: {result.stderr}")
            write_outputs_file({}, self.project_dir)
            return

        tf_outputs = json.loads(result.stdout)
        outputs = {}
        for out_def in output_defs:
            ref = out_def["ref"]
            if ref in tf_outputs:
                value = tf_outputs[ref].get("value", "")
                if isinstance(value, (list, dict)):
                    value = json.dumps(value)
                else:
                    value = str(value)
                outputs[ref] = value
                log(f"Output: {ref} → {value}")
            else:
                log(f"Warning: output '{ref}' not found in terraform outputs")

        write_outputs_file(outputs, self.project_dir)
