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
        for var_name, value in self.inputs.items():
            args.extend(["-var", f"{var_name}={value}"])
        # Tag maps are passed as JSON. CLI -var beats *.auto.tfvars, so the
        # consumer cannot override these via tfvars.
        args.extend(["-var", f"propeller_tags={json.dumps(self.propeller_tags)}"])
        args.extend(["-var", f"consumer_tags={json.dumps(self.consumer_tags)}"])
        return args

    def init(self) -> int:
        backend = self.project.get("deploy", {}).get("terraform", {}).get("backend", {})
        cmd = ["terraform", "init"]
        for key, value in backend.items():
            cmd.append(f"-backend-config={key}={substitute_env(str(value))}")
        return run_cmd(cmd, cwd=self.tf_dir)

    def plan(self) -> int:
        cmd = ["terraform", "plan", "-out=tfplan"] + self._var_args()
        return run_cmd(cmd, cwd=self.tf_dir)

    def apply(self) -> int:
        cmd = ["terraform", "apply", "-auto-approve"] + self._var_args()
        rc = run_cmd(cmd, cwd=self.tf_dir)
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
        # Write all terraform outputs, the Lambda picks what it needs
        # based on the pipeline definition.
        outputs = {}
        for name, data in tf_outputs.items():
            value = data.get("value", "")
            if isinstance(value, (list, dict)):
                value = json.dumps(value)
            else:
                value = str(value)
            outputs[name] = value
            log(f"Output: {name} → {value}")

        write_outputs_file(outputs, self.project_dir)
