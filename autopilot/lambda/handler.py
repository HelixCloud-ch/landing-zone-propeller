from __future__ import annotations

import json
import os

import boto3
from aws_durable_execution_sdk_python import (
    BatchResult,
    DurableContext,
    durable_execution,
)
from aws_durable_execution_sdk_python.config import CompletionConfig, Duration, ParallelConfig

ssm = boto3.client("ssm")
sts = boto3.client("sts")

ACCOUNT_SSM_PREFIX = "/propeller/accounts"
POLL_INTERVAL_SECONDS = 15
RUN_ROLE_NAME = "deploy-runner-run-role"
CODEBUILD_PROJECT_NAME = "deploy-runner"


def _get_parameter(name: str) -> str:
    return ssm.get_parameter(Name=name)["Parameter"]["Value"]


# --- DAG execution ---

def _build_dag(steps: list[dict]) -> dict[str, set[str]]:
    stage_projects = {s["project"] for s in steps}
    return {
        s["project"]: {d for d in s.get("depends_on", []) if d in stage_projects}
        for s in steps
    }


def _find_ready(dag: dict[str, set[str]], completed: set[str], failed: set[str], skipped: set[str]) -> list[str]:
    done = completed | failed | skipped
    running_or_done = done
    return sorted(
        p for p, deps in dag.items()
        if p not in running_or_done and deps <= completed
    )


def _find_dependents(dag: dict[str, set[str]], project: str) -> set[str]:
    result: set[str] = set()
    frontier = [project]
    while frontier:
        cur = frontier.pop()
        for p, deps in dag.items():
            if cur in deps and p not in result:
                result.add(p)
                frontier.append(p)
    return result


def _make_step_branch(step: dict, bundle_s3_uri: str, deploy_action: str):
    # Named steps/waits so the durable console shows each sub-operation per project.
    # ctx.wait() suspends without compute charges during polling.
    project = step["project"]

    def branch(ctx: DurableContext) -> dict:
        try:
            config = ctx.step(lambda _: _prepare(step), name=f"prepare:{project}")
            build_id = ctx.step(
                lambda _: _start_build(step, config, bundle_s3_uri, deploy_action),
                name=f"start:{project}",
            )

            while True:
                result = ctx.step(lambda _: _check_build(build_id, config), name=f"poll:{project}")
                if result["status"] in ("SUCCEEDED", "FAILED", "FAULT", "STOPPED", "TIMED_OUT"):
                    break
                ctx.wait(Duration.from_seconds(POLL_INTERVAL_SECONDS))

            if result["status"] != "SUCCEEDED":
                return {
                    "status": "failed", "project": project,
                    "error": f"Build {result['status']}", "build_id": build_id,
                }

            ctx.step(lambda _: _write_outputs(step, result["exportedVars"]), name=f"outputs:{project}")
            return {"status": "succeeded", "project": project, "build_id": build_id}

        except Exception as e:
            return {"status": "failed", "project": project, "error": str(e)}

    return branch


def _get_codebuild_client(account_id: str, region: str) -> boto3.client:
    role_arn = f"arn:aws:iam::{account_id}:role/{RUN_ROLE_NAME}"
    creds = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=f"propeller-{account_id}",
    )["Credentials"]
    return boto3.client(
        "codebuild",
        region_name=region,
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )


def _get_parameter_optional(name: str) -> str | None:
    try:
        return ssm.get_parameter(Name=name)["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        return None


def _prepare(step: dict) -> dict:
    target = step.get("target", "default")
    prefix = f"{ACCOUNT_SSM_PREFIX}/{target}"
    account_id = _get_parameter(f"{prefix}/account_id")
    region = _get_parameter_optional(f"{prefix}/region") or os.environ["AWS_REGION"]

    config = {
        "accountId": account_id,
        "region": region,
        "codebuildProject": CODEBUILD_PROJECT_NAME,
    }
    inputs = {}
    for inp in step.get("inputs", []):
        inputs[inp["var"]] = _get_parameter(inp["key"])
    config["inputs"] = inputs
    return config


def _start_build(step: dict, config: dict, bundle_s3_uri: str, deploy_action: str) -> str:
    cb = _get_codebuild_client(config["accountId"], config["region"])

    # Parse s3://bucket/key from the URI
    s3_parts = bundle_s3_uri.replace("s3://", "").split("/", 1)
    s3_location = f"{s3_parts[0]}/{s3_parts[1]}"

    env_vars = [
        {"name": "PROJECT_NAME", "value": step["project"], "type": "PLAINTEXT"},
        {"name": "DEPLOY_ACTION", "value": deploy_action, "type": "PLAINTEXT"},
        {"name": "AWS_ACCOUNT_ID", "value": config["accountId"], "type": "PLAINTEXT"},
        {"name": "AWS_REGION", "value": config["region"], "type": "PLAINTEXT"},
        {"name": "CONFIG_PATH", "value": f"config/{step['project']}.tfvars", "type": "PLAINTEXT"},
    ]
    for var_name, value in config.get("inputs", {}).items():
        env_vars.append({"name": f"PROPELLER_INPUT_{var_name}", "value": value, "type": "PLAINTEXT"})

    resp = cb.start_build(
        projectName=config["codebuildProject"],
        sourceTypeOverride="S3",
        sourceLocationOverride=s3_location,
        environmentVariablesOverride=env_vars,
    )
    return resp["build"]["id"]


def _check_build(build_id: str, config: dict) -> dict:
    cb = _get_codebuild_client(config["accountId"], config["region"])
    resp = cb.batch_get_builds(ids=[build_id])
    build = resp["builds"][0]
    return {
        "status": build["buildStatus"],
        "exportedVars": build.get("exportedEnvironmentVariables", []),
    }


def _write_outputs(step: dict, exported_vars: list) -> dict:
    output_defs = step.get("outputs", [])
    if not output_defs:
        return {"written": {}}

    outputs_json = "{}"
    for var in exported_vars:
        if var.get("name") == "PROPELLER_OUTPUTS_JSON":
            outputs_json = var.get("value", "{}")
            break

    outputs = json.loads(outputs_json)
    written = {}
    for out_def in output_defs:
        ref = out_def["ref"]
        if ref in outputs:
            ssm.put_parameter(Name=out_def["key"], Value=str(outputs[ref]), Type="String", Overwrite=True)
            written[ref] = out_def["key"]
    return {"written": written}


def run_stage(context: DurableContext, stage: dict, bundle_s3_uri: str, deploy_action: str) -> list[dict]:
    steps = stage["steps"]
    step_map = {s["project"]: s for s in steps}
    dag = _build_dag(steps)

    completed: set[str] = set()
    failed: set[str] = set()
    skipped: set[str] = set()
    results: dict[str, dict] = {}
    wave_num = 0

    while len(completed) + len(failed) + len(skipped) < len(dag):
        ready = _find_ready(dag, completed, failed, skipped)

        if not ready:
            break

        # Run ready steps in parallel (or single)
        branches = [_make_step_branch(step_map[p], bundle_s3_uri, deploy_action) for p in ready]

        # TODO: use named branches when supported — https://github.com/aws/aws-durable-execution-sdk-python/issues/303
        batch: BatchResult[dict] = context.parallel(
            branches,
            name=f"wave:{stage['name']}:{wave_num}",
            config=ParallelConfig(
                completion_config=CompletionConfig(tolerated_failure_count=len(branches)),
            ),
        )

        for item in batch.all:
            if item.status.value == "SUCCEEDED" and item.result:
                r = item.result
                project = r["project"]
                results[project] = r
                if r["status"] == "succeeded":
                    completed.add(project)
                else:
                    failed.add(project)
                    for dep in _find_dependents(dag, project):
                        if dep not in completed and dep not in failed:
                            skipped.add(dep)
                            results[dep] = {
                                "status": "skipped",
                                "project": dep,
                                "error": f"dependency '{project}' failed",
                            }
            elif item.status.value == "FAILED":
                # Branch itself threw — shouldn't happen since we catch exceptions
                project = ready[item.index]
                failed.add(project)
                results[project] = {
                    "status": "failed",
                    "project": project,
                    "error": str(item.error) if item.error else "unknown error",
                }

        wave_num += 1

    return list(results.values())


# --- Main handler ---

@durable_execution
def handler(event: dict, context: DurableContext):
    pipeline = event["pipeline"]
    bundle_s3_uri = event["bundle_s3_uri"]
    deploy_action = event.get("deploy_action", "apply")

    all_results: list[dict] = []
    stage_failed = False

    for stage in pipeline["stages"]:
        if stage_failed:
            for step in stage["steps"]:
                all_results.append({
                    "status": "skipped",
                    "project": step["project"],
                    "error": "previous stage failed",
                })
            continue

        stage_results = run_stage(context, stage, bundle_s3_uri, deploy_action)
        all_results.extend(stage_results)

        if any(r["status"] == "failed" for r in stage_results):
            stage_failed = True

    succeeded = sum(1 for r in all_results if r["status"] == "succeeded")
    failed_count = sum(1 for r in all_results if r["status"] == "failed")
    skipped_count = sum(1 for r in all_results if r["status"] == "skipped")

    return {
        "status": "failed" if failed_count > 0 else "succeeded",
        "summary": {
            "succeeded": succeeded,
            "failed": failed_count,
            "skipped": skipped_count,
        },
        "results": all_results,
    }
