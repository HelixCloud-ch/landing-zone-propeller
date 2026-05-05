variable "region" {
  type        = string
  description = "AWS region for the state machine."
}

variable "sfn_name" {
  type        = string
  description = "Name of the Step Functions state machine and prefix for related resources."
  default     = "landing-zone-propeller-sfn"
}

variable "deploy_runner_project_name" {
  type        = string
  description = "Name of the local deploy-runner CodeBuild project."
  default     = "deploy-runner"
}

variable "cross_account_run_role_name" {
  type        = string
  description = "Name of the run-role in target accounts (created by deploy-runner product)."
  default     = "deploy-runner-run-role"
}

variable "organization_id" {
  type        = string
  description = "AWS Organizations ID to scope cross-account assume-role."
}
