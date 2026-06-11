variable "region" {
  type        = string
  description = "AWS region."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Cluster ───────────────────────────────────────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Cluster name. Used to locate the worker IAM role."
}

# ── ECR ───────────────────────────────────────────────────────────────────────

variable "ecr_account_id" {
  type        = string
  description = "AWS account ID hosting the ECR registry."
}

variable "ecr_region" {
  type        = string
  description = "Region of the ECR registry. Defaults to same as deployment region."
  default     = null
}

# ── Worker role ───────────────────────────────────────────────────────────────

variable "worker_role_name" {
  type        = string
  description = "Name of the ROSA HCP worker node IAM role. Defaults to the ROSA HCP convention."
  default     = null
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
