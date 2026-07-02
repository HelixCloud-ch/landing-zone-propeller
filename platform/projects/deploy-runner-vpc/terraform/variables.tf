variable "region" {
  type        = string
  description = "AWS region."
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID to attach the CodeBuild project to."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs where CodeBuild will run (needs NAT or VPC endpoints for AWS APIs)."
}

# ── Pipeline inputs (JSON subnet map) ─────────────────────────────────────────

variable "subnet_ids_json" {
  type        = string
  description = "JSON string of subnet tier map (from VPC project output). Used when subnet_ids is not set directly."
  default     = ""
}

variable "subnet_tier" {
  type        = string
  description = "Key in the subnet map to use for the CodeBuild subnets."
  default     = "app"
}

# ── Runner configuration ──────────────────────────────────────────────────────

variable "project_name" {
  type        = string
  description = "Name of the CodeBuild project. Must match the `runner` value used in pipeline steps."
}

variable "compute_type" {
  type        = string
  description = "CodeBuild compute type."
  default     = "BUILD_GENERAL1_SMALL"
}

variable "image" {
  type        = string
  description = "CodeBuild build environment image."
  default     = "aws/codebuild/amazonlinux-x86_64-standard:6.0"
}

variable "timeout_minutes" {
  type        = number
  description = "Default build timeout in minutes."
  default     = 60
}

# ── Cross-account access ──────────────────────────────────────────────────────

variable "caller_arn" {
  type        = string
  description = "ARN of the autopilot Lambda role in the operations account. Required for cross-account invocation."
}

variable "caller_account_id" {
  type        = string
  description = "AWS account ID of the operations account."
}

# ── S3 access ─────────────────────────────────────────────────────────────────

variable "bundle_bucket_name" {
  type        = string
  description = "S3 bucket name in the operations account containing propeller bundles (read access)."
}

variable "state_bucket_name" {
  type        = string
  description = "S3 bucket name for terraform state in this account (read/write access). Defaults to the standard naming convention."
  default     = ""
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  type    = map(string)
  default = {}
}

variable "consumer_tags" {
  type    = map(string)
  default = {}
}

variable "propeller_tags" {
  type    = map(string)
  default = {}
}
