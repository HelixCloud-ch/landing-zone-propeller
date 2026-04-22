locals {
  account_id       = data.aws_caller_identity.current.account_id
  local_cb_arn     = "arn:aws:codebuild:${data.aws_region.current.name}:${local.account_id}:project/${var.deploy_runner_project_name}"
  eventbridge_rule = "arn:aws:events:${data.aws_region.current.name}:${local.account_id}:rule/StepFunctionsGetEventForCodeBuildStartBuildRule"
  run_role_pattern = "arn:aws:iam::*:role/${var.cross_account_run_role_name}"
}
