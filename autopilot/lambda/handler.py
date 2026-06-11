from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import boto3
from aws_durable_execution_sdk_python import (
    BatchResult,
    DurableContext,
    durable_execution,
)
from aws_durable_execution_sdk_python.config import (
    CompletionConfig,
    Duration,
    ParallelConfig,
)

ssm = boto3.client("ssm")
sts = boto3.client("sts")

ACCOUNTS_SSM_PREFIX = "/propeller/accounts"
EMPTY_SENTINEL = "__EMPTY__"

CODEBUILD_PROJECT_NAME = "deploy-runner"
RUN_ROLE_NAME = "deploy-runner-run-role"

POLL_INTERVAL_SECONDS = 15

_BUILDSPEC_PATH = Path(__file__).parent / "buildspec.yml"
BUILDSPEC = _BUILDSPEC_PATH.read_text()


@dataclass
class PipelineCtx:
    bundle_s3_uri: str
    deploy_action: str
    namespace: str
    propeller_version: str
    git_sha: str
    consumer_tags: dict


def _get_parameter(name: str) -> str:
    return ssm.get_parameter(Name=name)["Parameter"]["Value"]


def _get_parameter_optional(name: str) -> str | None:
    try:
        return ssm.get_parameter(Name=name)["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        return None


# --- DAG execution ---


def _build_dag(steps: list[dict]) -> dict[str, set[str]]:
    stage_projects = {s["project"] for s in steps}
    return {
        s["project"]: {d for d in s.get("depends_on", []) if d in stage_projects}
        for s in steps
    }


def _find_ready(
    dag: dict[str, set[str]], completed: set[str], failed: set[str], skipped: set[str]
) -> list[str]:
    done = completed | failed | skipped
    return sorted(p for p, deps in dag.items() if p not in done and deps <= completed)


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


def _make_step_branch(step: dict, pctx: PipelineCtx):
    project = step["project"]

    def branch(ctx: DurableContext) -> dict:
        try:
            config = ctx.step(lambda _: _prepare(step), name=f"prepare:{project}")
            build_id = ctx.step(
                lambda _: _start_build(step, config, pctx),
                name=f"start:{project}",
            )

            while True:
                result = ctx.step(
                    lambda _: _check_build(build_id, config), name=f"poll:{project}"
                )
                if result["status"] in (
                    "SUCCEEDED",
                    "FAILED",
                    "FAULT",
                    "STOPPED",
                    "TIMED_OUT",
                ):
                    break
                ctx.wait(Duration.from_seconds(POLL_INTERVAL_SECONDS))

            # Fetch and log the full build output
            try:
                build_logs = ctx.step(
                    lambda _: _fetch_build_logs(build_id, config),
                    name=f"logs:{project}",
                )
                if result["status"] != "SUCCEEDED":
                    ctx.logger.error(
                        f"✗ [{project}] Build {result['status']}\n{build_logs}"
                    )
                else:
                    ctx.logger.info(
                        f"✓ [{project}] Build {result['status']}\n{build_logs}"
                    )
            except Exception as log_err:
                ctx.logger.warning(f"[{project}] Failed to fetch build logs: {log_err}")

            target = step.get("target")
            account_id = config.get("accountId")

            if result["status"] != "SUCCEEDED":
                return {
                    "status": "failed",
                    "project": project,
                    "target": target,
                    "account_id": account_id,
                    "error": f"Build {result['status']}",
                    "build_id": build_id,
                }

            if pctx.deploy_action == "apply":
                ctx.step(
                    lambda _: _write_outputs(
                        step, result["exportedVars"], build_id, pctx
                    ),
                    name=f"outputs:{project}",
                )

            return {
                "status": "succeeded",
                "project": project,
                "target": target,
                "account_id": account_id,
                "build_id": build_id,
            }

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


def _prepare(step: dict) -> dict:
    target = step.get("target", "default")
    prefix = f"{ACCOUNTS_SSM_PREFIX}/{target}"
    account_id = _get_parameter(f"{prefix}/id")
    region = _get_parameter_optional(f"{prefix}/region") or os.environ["AWS_REGION"]

    config = {
        "accountId": account_id,
        "region": region,
        "codebuildProject": CODEBUILD_PROJECT_NAME,
    }
    inputs = {}
    blob_cache: dict[str, dict] = {}
    for inp in step.get("inputs", []):
        field = inp.get("field")
        if field:
            key = inp["key"]
            if key not in blob_cache:
                blob_cache[key] = json.loads(_get_parameter(key))["outputs"]
            inputs[inp["var"]] = str(blob_cache[key].get(field, ""))
        else:
            raw = _get_parameter(inp["key"])
            inputs[inp["var"]] = "" if raw == EMPTY_SENTINEL else raw
    config["inputs"] = inputs
    return config


def _start_build(step: dict, config: dict, pctx: PipelineCtx) -> str:
    cb = _get_codebuild_client(config["accountId"], config["region"])

    s3_parts = pctx.bundle_s3_uri.replace("s3://", "").split("/", 1)
    s3_location = f"{s3_parts[0]}/{s3_parts[1]}"

    env_vars = [
        {"name": "PROJECT_NAME", "value": step["project"], "type": "PLAINTEXT"},
        {"name": "PROPELLER_NAMESPACE", "value": pctx.namespace, "type": "PLAINTEXT"},
        {"name": "DEPLOY_ACTION", "value": pctx.deploy_action, "type": "PLAINTEXT"},
        {"name": "AWS_ACCOUNT_ID", "value": config["accountId"], "type": "PLAINTEXT"},
        {"name": "AWS_REGION", "value": config["region"], "type": "PLAINTEXT"},
        {
            "name": "PROPELLER_FRAMEWORK_TAGS_JSON",
            "value": json.dumps(step.get("propeller_tags") or {}),
            "type": "PLAINTEXT",
        },
        {
            "name": "PROPELLER_CONSUMER_TAGS_JSON",
            "value": json.dumps(pctx.consumer_tags),
            "type": "PLAINTEXT",
        },
    ]
    for var_name, value in config.get("inputs", {}).items():
        env_vars.append(
            {"name": f"PROPELLER_INPUT_{var_name}", "value": value, "type": "PLAINTEXT"}
        )

    build_kwargs = {
        "projectName": config["codebuildProject"],
        "sourceTypeOverride": "S3",
        "sourceLocationOverride": s3_location,
        "buildspecOverride": BUILDSPEC,
        "environmentVariablesOverride": env_vars,
    }
    if step.get("timeout"):
        build_kwargs["timeoutInMinutesOverride"] = step["timeout"]

    resp = cb.start_build(**build_kwargs)
    return resp["build"]["id"]


def _check_build(build_id: str, config: dict) -> dict:
    cb = _get_codebuild_client(config["accountId"], config["region"])
    resp = cb.batch_get_builds(ids=[build_id])
    build = resp["builds"][0]
    return {
        "status": build["buildStatus"],
        "exportedVars": build.get("exportedEnvironmentVariables", []),
    }


def _fetch_build_logs(build_id: str, config: dict) -> str:
    """Fetch the full CloudWatch Logs output for a completed CodeBuild build."""
    account_id = config["accountId"]
    region = config["region"]

    # Get log location from the build
    cb = _get_codebuild_client(account_id, region)
    resp = cb.batch_get_builds(ids=[build_id])
    build = resp["builds"][0]

    logs_info = build.get("logs", {})
    group_name = logs_info.get("groupName")
    stream_name = logs_info.get("streamName")

    if not group_name or not stream_name:
        return "(no logs available)"

    # Create a CloudWatch Logs client with the same assumed credentials
    role_arn = f"arn:aws:iam::{account_id}:role/{RUN_ROLE_NAME}"
    creds = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=f"propeller-logs-{account_id}",
    )["Credentials"]
    logs_client = boto3.client(
        "logs",
        region_name=region,
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )

    # Fetch all log events (paginate)
    lines: list[str] = []
    kwargs = {
        "logGroupName": group_name,
        "logStreamName": stream_name,
        "startFromHead": True,
    }
    while True:
        resp = logs_client.get_log_events(**kwargs)
        events = resp.get("events", [])
        if not events:
            break
        for event in events:
            lines.append(event["message"])
        next_token = resp.get("nextForwardToken")
        if next_token == kwargs.get("nextToken"):
            break
        kwargs["nextToken"] = next_token

    return "\n".join(lines) if lines else "(empty log stream)"


def _write_outputs(
    step: dict, exported_vars: list, build_id: str, pctx: PipelineCtx
) -> dict:
    output_defs = step.get("outputs", [])

    outputs_json = "{}"
    for var in exported_vars:
        if var.get("name") == "PROPELLER_OUTPUTS_JSON":
            outputs_json = var.get("value", "{}")
            break

    outputs = json.loads(outputs_json)
    if not outputs and output_defs:
        print(
            f"[propeller] Warning: PROPELLER_OUTPUTS_JSON is empty for {step['project']}, "
            f"expected outputs: {[o['ref'] for o in output_defs]}"
        )

    blob_outputs = {}
    written = {}

    for out_def in output_defs:
        ref = out_def["ref"]
        field = out_def.get("field")
        value = outputs.get(ref)

        if value is None:
            print(
                f"[propeller] Warning: output '{ref}' not found in build outputs for {step['project']}"
            )
            continue

        if field:
            blob_outputs[field] = value
        else:
            str_value = str(value)
            ssm_value = EMPTY_SENTINEL if str_value == "" else str_value
            ssm.put_parameter(
                Name=out_def["key"],
                Value=ssm_value,
                Type="String",
                Overwrite=True,
            )
            if str_value == "":
                print(
                    f"[propeller] Output '{ref}' is empty for {step['project']}, stored as sentinel"
                )
            written[ref] = out_def["key"]

    # Always write the project blob (outputs + meta)
    blob_key = (
        f"/propeller/{pctx.namespace}/{step['project']}"
        if pctx.namespace
        else f"/propeller/{step['project']}"
    )
    blob_value = {
        "outputs": blob_outputs,
        "meta": {
            "propeller_version": pctx.propeller_version,
            "deployed_at": datetime.now(timezone.utc).isoformat(),
            "build_id": build_id,
            "git_sha": pctx.git_sha,
        },
    }
    ssm.put_parameter(
        Name=blob_key,
        Value=json.dumps(blob_value),
        Type="String",
        Overwrite=True,
    )
    for field in blob_outputs:
        written[field] = f"{blob_key}[{field}]"

    return {"written": written}


def run_stage(context: DurableContext, stage: dict, pctx: PipelineCtx) -> list[dict]:
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

        branches = [_make_step_branch(step_map[p], pctx) for p in ready]

        # TODO: use named branches when supported — https://github.com/aws/aws-durable-execution-sdk-python/issues/303
        batch: BatchResult[dict] = context.parallel(
            branches,
            name=f"wave:{stage['name']}:{wave_num}",
            config=ParallelConfig(
                completion_config=CompletionConfig(
                    tolerated_failure_count=len(branches)
                ),
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
    context.logger.info(f"▶ Pipeline triggered: action={event.get('deploy_action', 'unknown')}, namespace={event.get('pipeline', {}).get('namespace', '?')}")

    pipeline = event["pipeline"]
    bundle_s3_uri = event["bundle_s3_uri"]
    only = set(event.get("only", []))

    pctx = PipelineCtx(
        bundle_s3_uri=bundle_s3_uri,
        deploy_action=event.get("deploy_action", "apply"),
        namespace=pipeline.get("namespace", ""),
        propeller_version=pipeline.get("propeller_version", "unknown"),
        git_sha=event.get("git_sha", ""),
        consumer_tags=pipeline.get("consumer_tags") or {},
    )

    # Filter pipeline to only the specified projects (if set)
    if only:
        for stage in pipeline["stages"]:
            stage["steps"] = [s for s in stage["steps"] if s["project"] in only]
        pipeline["stages"] = [s for s in pipeline["stages"] if s["steps"]]

    all_results: list[dict] = []
    stage_failed = False

    for stage in pipeline["stages"]:
        if stage_failed:
            for step in stage["steps"]:
                all_results.append(
                    {
                        "status": "skipped",
                        "project": step["project"],
                        "error": "previous stage failed",
                    }
                )
            continue

        stage_results = run_stage(context, stage, pctx)
        all_results.extend(stage_results)

        # Log stage summary at handler level
        s_ok = sum(1 for r in stage_results if r["status"] == "succeeded")
        s_fail = sum(1 for r in stage_results if r["status"] == "failed")
        s_skip = sum(1 for r in stage_results if r["status"] == "skipped")
        if s_fail:
            failed_projects = [r["project"] for r in stage_results if r["status"] == "failed"]
            context.logger.error(f"✗ Stage '{stage['name']}': {s_ok} succeeded, {s_fail} failed ({', '.join(failed_projects)}), {s_skip} skipped")
        else:
            context.logger.info(f"✓ Stage '{stage['name']}': {s_ok} succeeded")

        if s_fail:
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
