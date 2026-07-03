from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import boto3
from aws_durable_execution_sdk_python import (
    BatchResult,
    DurableContext,
    StepContext,
    __version__ as _durable_sdk_version,
    durable_execution,
)
from aws_durable_execution_sdk_python.config import (
    CompletionConfig,
    Duration,
    ParallelConfig,
)

print(f"[propeller] Durable Execution SDK version: {_durable_sdk_version}")

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

            def do_prepare(step_ctx: StepContext) -> dict:
                step_ctx.logger.info(f"[{project}] Preparing build config")
                result = _prepare(step)
                step_ctx.logger.info(
                    f"[{project}] Target account={result['accountId']}, region={result['region']}"
                )
                return result

            config = ctx.step(do_prepare, name=f"prepare:{project}")

            def do_start_build(step_ctx: StepContext) -> str:
                step_ctx.logger.info(
                    f"[{project}] Starting CodeBuild in {config['accountId']}"
                )
                bid = _start_build(step, config, pctx)
                step_ctx.logger.info(f"[{project}] Build started: {bid}")
                return bid

            build_id = ctx.step(do_start_build, name=f"start:{project}")

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

                def do_fetch_logs(step_ctx: StepContext) -> str:
                    step_ctx.logger.info(f"[{project}] Fetching build logs")
                    logs = _fetch_build_logs(build_id, config)
                    if result["status"] != "SUCCEEDED":
                        step_ctx.logger.error(
                            f"[{project}] ✗ Build {result['status']}",
                            extra={"build_id": build_id},
                        )
                    else:
                        step_ctx.logger.info(
                            f"[{project}] ✓ Build {result['status']}",
                            extra={"build_id": build_id},
                        )
                    return logs

                build_logs = ctx.step(do_fetch_logs, name=f"logs:{project}")
                if result["status"] != "SUCCEEDED":
                    ctx.logger.error(
                        f"[{project}] ✗ Build {result['status']}\n{build_logs}"
                    )
                else:
                    ctx.logger.info(
                        f"[{project}] ✓ Build {result['status']}\n{build_logs}"
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

                def do_write_outputs(step_ctx: StepContext) -> dict:
                    step_ctx.logger.info(f"[{project}] Writing outputs to SSM")
                    written = _write_outputs(
                        step, result["exportedVars"], build_id, pctx
                    )
                    step_ctx.logger.info(
                        f"[{project}] Outputs written",
                        extra={"keys": list(written.get("written", {}).keys())},
                    )
                    return written

                ctx.step(do_write_outputs, name=f"outputs:{project}")

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


def _get_codebuild_client(
    account_id: str, region: str, runner: str | None = None
) -> boto3.client:
    run_role = f"{runner}-run-role" if runner else RUN_ROLE_NAME
    role_arn = f"arn:aws:iam::{account_id}:role/{run_role}"
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
        "codebuildProject": step.get("runner") or CODEBUILD_PROJECT_NAME,
        "runner": step.get("runner"),
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
    cb = _get_codebuild_client(
        config["accountId"], config["region"], config.get("runner")
    )

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
    cb = _get_codebuild_client(
        config["accountId"], config["region"], config.get("runner")
    )
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
    cb = _get_codebuild_client(account_id, region, config.get("runner"))
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


def _run_stage_sleep_wake(
    context: DurableContext, stage: dict, pctx: PipelineCtx
) -> list[dict]:
    """Execute a stage in sleep or wake mode.

    For each step, determines behavior based on:
    - Step-level `sleep: true/false` (consumer opt-in)
    - Project-level `sleep_config.action` (framework capability)

    Dispatches to: skip, terraform destroy/apply, or command execution.
    """
    is_wake = pctx.deploy_action == "wake"
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

        branches = []
        ready_projects = []

        for project in ready:
            step = step_map[project]
            behavior = _determine_sleep_behavior(step)

            if behavior == "skip":
                # No-op — project doesn't participate in sleep/wake
                skipped.add(project)
                results[project] = {
                    "status": "skipped",
                    "project": project,
                    "error": "sleep: skip (not participating)",
                }
                context.logger.info(f"[{project}] Skipped (sleep: skip)")
                continue
            elif behavior == "destroy":
                branches.append(_make_sleep_destroy_branch(step, pctx, is_wake))
                ready_projects.append(project)
            elif behavior == "command":
                branches.append(_make_sleep_command_branch(step, pctx, is_wake))
                ready_projects.append(project)

        if not branches:
            # All ready projects were skipped, loop will pick up next wave
            continue

        batch: BatchResult[dict] = context.parallel(
            branches,
            name=f"sleep-wave:{stage['name']}:{wave_num}",
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
                project = ready_projects[item.index]
                failed.add(project)
                results[project] = {
                    "status": "failed",
                    "project": project,
                    "error": str(item.error) if item.error else "unknown error",
                }

        wave_num += 1

    return list(results.values())


# --- Sleep/wake support ---


def _determine_sleep_behavior(step: dict) -> str:
    """Determine what to do with a project during sleep/wake.

    Returns: "destroy", "command", or "skip".
    """
    # Consumer must opt in via `sleep: true` on the step
    if not step.get("sleep", False):
        return "skip"

    # Framework project.yaml defines capability via `sleep_config` (injected at resolve time)
    sleep_config = step.get("sleep_config")
    if not sleep_config:
        return "skip"

    return sleep_config.get("action", "skip")


def _resolve_command_vars(command: str, step: dict, pctx: PipelineCtx) -> str:
    """Resolve ${TF_OUTPUT_*}, ${AWS_REGION}, ${AWS_ACCOUNT_ID}, etc. in a command string."""
    # Resolve basic variables
    target = step.get("target", "default")
    prefix = f"{ACCOUNTS_SSM_PREFIX}/{target}"
    account_id = _get_parameter(f"{prefix}/id")
    region = _get_parameter_optional(f"{prefix}/region") or os.environ["AWS_REGION"]

    command = command.replace("${AWS_REGION}", region)
    command = command.replace("${AWS_ACCOUNT_ID}", account_id)
    command = command.replace("${PROPELLER_NAMESPACE}", pctx.namespace)
    command = command.replace("${PROJECT_NAME}", step["project"])

    # Resolve ${TF_OUTPUT_*} from the project's SSM blob
    if "${TF_OUTPUT_" in command:
        blob_key = (
            f"/propeller/{pctx.namespace}/{step['project']}"
            if pctx.namespace
            else f"/propeller/{step['project']}"
        )
        try:
            blob = json.loads(_get_parameter(blob_key))
            outputs = blob.get("outputs", {})
            # Replace all ${TF_OUTPUT_<name>} patterns
            for match in re.finditer(r"\$\{TF_OUTPUT_(\w+)\}", command):
                var_name = match.group(1)
                value = str(outputs.get(var_name, ""))
                command = command.replace(match.group(0), value)
        except Exception:
            pass  # If blob doesn't exist, leave placeholders as-is

    return command


def _make_sleep_command_branch(step: dict, pctx: PipelineCtx, is_wake: bool):
    """Create a branch that executes a sleep/wake command via the deploy runner."""
    project = step["project"]
    sleep_config = step.get("sleep_config", {})
    command_key = "wake_command" if is_wake else "command"
    raw_command = sleep_config.get(command_key, "")

    def branch(ctx: DurableContext) -> dict:
        try:

            def do_resolve_and_run(step_ctx: StepContext) -> dict:
                resolved_cmd = _resolve_command_vars(raw_command, step, pctx)
                step_ctx.logger.info(
                    f"[{project}] Running {'wake' if is_wake else 'sleep'} command"
                )

                # Prepare config for the deploy runner
                config = _prepare(step)

                # Build a synthetic buildspec that just runs the command
                command_buildspec = f"""version: 0.2
phases:
  build:
    commands:
      - |
        {resolved_cmd}
"""
                cb = _get_codebuild_client(
                    config["accountId"], config["region"], config.get("runner")
                )

                s3_parts = pctx.bundle_s3_uri.replace("s3://", "").split("/", 1)
                s3_location = f"{s3_parts[0]}/{s3_parts[1]}"

                env_vars = [
                    {
                        "name": "PROJECT_NAME",
                        "value": project,
                        "type": "PLAINTEXT",
                    },
                    {
                        "name": "PROPELLER_NAMESPACE",
                        "value": pctx.namespace,
                        "type": "PLAINTEXT",
                    },
                    {
                        "name": "AWS_ACCOUNT_ID",
                        "value": config["accountId"],
                        "type": "PLAINTEXT",
                    },
                    {
                        "name": "AWS_REGION",
                        "value": config["region"],
                        "type": "PLAINTEXT",
                    },
                ]

                build_kwargs = {
                    "projectName": config["codebuildProject"],
                    "sourceTypeOverride": "S3",
                    "sourceLocationOverride": s3_location,
                    "buildspecOverride": command_buildspec,
                    "environmentVariablesOverride": env_vars,
                }

                resp = cb.start_build(**build_kwargs)
                return {"build_id": resp["build"]["id"], "config": config}

            start_result = ctx.step(do_resolve_and_run, name=f"cmd-start:{project}")
            build_id = start_result["build_id"]
            config = start_result["config"]

            # Poll for completion
            while True:
                result = ctx.step(
                    lambda _: _check_build(build_id, config),
                    name=f"cmd-poll:{project}",
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

            action_label = "wake" if is_wake else "sleep"
            if result["status"] != "SUCCEEDED":
                ctx.logger.error(
                    f"[{project}] ✗ {action_label} command {result['status']}"
                )
                return {
                    "status": "failed",
                    "project": project,
                    "error": f"{action_label} command {result['status']}",
                    "build_id": build_id,
                }

            ctx.logger.info(f"[{project}] ✓ {action_label} command succeeded")
            return {
                "status": "succeeded",
                "project": project,
                "build_id": build_id,
            }

        except Exception as e:
            return {"status": "failed", "project": project, "error": str(e)}

    return branch


def _make_sleep_destroy_branch(step: dict, pctx: PipelineCtx, is_wake: bool):
    """Create a branch that runs terraform destroy (sleep) or apply (wake)."""
    # Reuse the normal step branch but override the deploy action
    override_action = "apply" if is_wake else "destroy"
    override_pctx = PipelineCtx(
        bundle_s3_uri=pctx.bundle_s3_uri,
        deploy_action=override_action,
        namespace=pctx.namespace,
        propeller_version=pctx.propeller_version,
        git_sha=pctx.git_sha,
        consumer_tags=pctx.consumer_tags,
    )
    return _make_step_branch(step, override_pctx)


def _write_pipeline_state(namespace: str, state: str) -> None:
    """Write the pipeline state to SSM for cross-pipeline coordination."""
    ssm.put_parameter(
        Name=f"/propeller/{namespace}/state",
        Value=state,
        Type="String",
        Overwrite=True,
    )


# --- Main handler ---


@durable_execution
def handler(event: dict, context: DurableContext):
    context.logger.info(
        f"▶ Pipeline triggered: action={event.get('deploy_action', 'unknown')}, namespace={event.get('pipeline', {}).get('namespace', '?')}"
    )

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

    # Step 1: Reverse stage order for sleep (tear down in reverse dependency order)
    stages = pipeline["stages"]
    if pctx.deploy_action == "sleep":
        stages = list(reversed(stages))

    all_results: list[dict] = []
    stage_failed = False

    for stage in stages:
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

        # Step 2: For sleep/wake, filter and dispatch per-project behavior
        if pctx.deploy_action in ("sleep", "wake"):
            stage_results = _run_stage_sleep_wake(context, stage, pctx)
        else:
            stage_results = run_stage(context, stage, pctx)

        all_results.extend(stage_results)

        # Log stage summary at handler level
        s_ok = sum(1 for r in stage_results if r["status"] == "succeeded")
        s_fail = sum(1 for r in stage_results if r["status"] == "failed")
        s_skip = sum(1 for r in stage_results if r["status"] == "skipped")
        if s_fail:
            failed_projects = [
                r["project"] for r in stage_results if r["status"] == "failed"
            ]
            context.logger.error(
                f"[stage:{stage['name']}] ✗ {s_ok} succeeded, {s_fail} failed ({', '.join(failed_projects)}), {s_skip} skipped"
            )
        else:
            context.logger.info(f"[stage:{stage['name']}] ✓ {s_ok} succeeded, {s_skip} skipped")

        if s_fail:
            stage_failed = True

    succeeded = sum(1 for r in all_results if r["status"] == "succeeded")
    failed_count = sum(1 for r in all_results if r["status"] == "failed")
    skipped_count = sum(1 for r in all_results if r["status"] == "skipped")

    # Step 4: Write pipeline state to SSM after completion
    if pctx.deploy_action in ("sleep", "wake") and pctx.namespace:
        final_state = "sleeping" if pctx.deploy_action == "sleep" else "running"
        if failed_count == 0:
            _write_pipeline_state(pctx.namespace, final_state)
            context.logger.info(
                f"Pipeline state written: /propeller/{pctx.namespace}/state = {final_state}"
            )
        else:
            context.logger.warning(
                f"Pipeline had failures — state not updated (remains as-is)"
            )

    return {
        "status": "failed" if failed_count > 0 else "succeeded",
        "summary": {
            "succeeded": succeeded,
            "failed": failed_count,
            "skipped": skipped_count,
        },
        "results": all_results,
    }
