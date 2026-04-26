"""CloudFormation deploy runner."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from .runner import DeployRunner, log, run_cmd, substitute_env, write_outputs_file


class CloudFormationRunner(DeployRunner):
    @property
    def _deploy_cfg(self) -> dict:
        return self.project.get("deploy", {}).get("cloudformation", {})

    @property
    def _stack_name(self) -> str:
        return substitute_env(self._deploy_cfg.get("stack_name", self.project["name"]))

    @property
    def _region(self) -> str:
        return substitute_env(
            self._deploy_cfg.get("region", os.environ.get("AWS_REGION", "us-east-1"))
        )

    @property
    def _template_path(self) -> Path:
        return self.project_dir / self._deploy_cfg.get(
            "template", "cloudformation/template.yaml"
        )

    def _param_overrides(self) -> list[str]:
        params = []
        for var_name, value in self.inputs.items():
            params.append(f"{var_name}={value}")
        if self.config and Path(self.config).exists():
            for line in Path(self.config).read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, _, val = line.partition("=")
                    params.append(f"{key.strip()}={val.strip().strip('"')}")
        return params

    def _deploy_cmd(self, no_execute: bool = False) -> list[str]:
        cmd = [
            "aws",
            "cloudformation",
            "deploy",
            "--stack-name",
            self._stack_name,
            "--template-file",
            str(self._template_path),
            "--region",
            self._region,
            "--capabilities",
            "CAPABILITY_NAMED_IAM",
            "--no-fail-on-empty-changeset",
        ]
        params = self._param_overrides()
        if params:
            cmd.extend(["--parameter-overrides"] + params)
        if no_execute:
            cmd.append("--no-execute-changeset")
        return cmd

    def init(self) -> int:
        log("CloudFormation: no init step needed")
        return 0

    def plan(self) -> int:
        return run_cmd(self._deploy_cmd(no_execute=True), cwd=self.project_dir)

    def apply(self) -> int:
        rc = run_cmd(self._deploy_cmd(), cwd=self.project_dir)
        if rc != 0:
            return rc
        self._write_outputs()
        return 0

    def destroy(self) -> int:
        return run_cmd(
            [
                "aws",
                "cloudformation",
                "delete-stack",
                "--stack-name",
                self._stack_name,
                "--region",
                self._region,
            ]
        )

    def outputs(self) -> int:
        return run_cmd(
            [
                "aws",
                "cloudformation",
                "describe-stacks",
                "--stack-name",
                self._stack_name,
                "--region",
                self._region,
                "--query",
                "Stacks[0].Outputs",
            ]
        )

    def _write_outputs(self) -> None:
        output_defs = self.project.get("outputs", [])
        if not output_defs:
            write_outputs_file({}, self.project_dir)
            return

        result = subprocess.run(
            [
                "aws",
                "cloudformation",
                "describe-stacks",
                "--stack-name",
                self._stack_name,
                "--region",
                self._region,
                "--query",
                "Stacks[0].Outputs",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            log(f"Warning: describe-stacks failed: {result.stderr}")
            write_outputs_file({}, self.project_dir)
            return

        cfn_outputs = json.loads(result.stdout) or []
        cfn_map = {o["OutputKey"]: o["OutputValue"] for o in cfn_outputs}

        outputs = {}
        for out_def in output_defs:
            ref = out_def["ref"]
            if ref in cfn_map:
                outputs[ref] = cfn_map[ref]
                log(f"Output: {ref} → {cfn_map[ref]}")
            else:
                log(f"Warning: output '{ref}' not found in stack outputs")

        write_outputs_file(outputs, self.project_dir)
