variable "region" {
  type        = string
  description = "AWS region of the vault. Must be one of the regions in the backup policy."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "vault_name" {
  type        = string
  description = "Name of the vault. For a source vault, must match backup-policies.source_vault_name."
  default     = "propeller-backup"
}

variable "role_name" {
  type        = string
  description = "Name of the AWS Backup role. For a source vault, must match backup-policies.iam_role_name."
  default     = "propeller-backup-role"
}

variable "enable_restores" {
  type        = bool
  description = "Attach the AWS managed restore policy to the role. Needed where restores run."
  default     = true
}

variable "vault_lock" {
  type = object({
    min_retention_days = number
    max_retention_days = number
  })
  description = "Governance-mode Vault Lock window; copy retention must fall inside it. Null (default) disables it."
  default     = null
}

variable "kms_key_arn" {
  type        = string
  description = "Existing CMK (e.g. managed centrally). Null creates one; see README for its key policy."
  default     = null
}

variable "kms_key_alias" {
  type        = string
  description = "Alias (without 'alias/') for the created key. Defaults to backup/<vault_name>."
  default     = null
}

# ── Cross-account access (vault policy and created key) ──────────────────────

variable "peer_account_id" {
  type        = string
  description = "Single peer account ID, for pipeline wiring (e.g. the backup account's account_id)."
  default     = null
}

variable "peer_account_ids" {
  type        = list(string)
  description = "Additional peer account IDs."
  default     = []

  validation {
    condition     = var.peer_account_id != null || length(var.peer_account_ids) > 0 || var.organization_id != null
    error_message = "Set at least one of peer_account_id, peer_account_ids or organization_id."
  }
}

variable "organization_id" {
  type        = string
  description = "Grant every principal in this organization, e.g. from workload-parameters.organization_id."
  default     = null
}

variable "org_paths" {
  type        = list(string)
  description = "Narrows organization_id to these aws:PrincipalOrgPaths patterns (e.g. o-xxx/r-xxx/ou-xxx/*)."
  default     = []
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Per-project tags applied to all resources via provider default_tags."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Pipeline-wide tags applied to all resources via provider default_tags."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Framework-managed tags applied to all resources via provider default_tags."
  default     = {}
}
