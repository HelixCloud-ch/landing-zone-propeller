# ── Region ────────────────────────────────────────────────────────────────────

variable "region" {
  type        = string
  description = "AWS region where the IAM roles live."
}

variable "ecr_region" {
  type        = string
  description = "AWS region of the shared ECR account. Defaults to var.region when null."
  default     = null
}

# ── Pipeline inputs (from the eks-cluster outputs) ────────────────────────────

variable "pod_execution_role_name" {
  type        = string
  description = "Name of the Fargate pod execution role the ECR pull policy is attached to. Sourced from the eks-cluster project output pod_execution_role_name (or a keyed entry of pod_execution_role_names). Null when the cluster has no Fargate profiles."
  default     = null
}

variable "additional_role_names" {
  type        = list(string)
  description = "Additional IAM role names to attach the ECR pull policy to. Use this for the node role on EC2 clusters (eks-cluster.node_role_name) or any other role that needs cross-account ECR pull."
  default     = []
}

# ── ECR ────────────────────────────────────────────────────────────────────────

variable "ecr_account_id" {
  type        = string
  description = "AWS account ID that hosts the shared ECR registry. Must be set in config.auto.tfvars; no default."
}

# ── Tagging ────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Base tags merged into the provider default_tags block."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Consumer-specific tags merged into the provider default_tags block."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Propeller framework tags merged into the provider default_tags block."
  default     = {}
}
