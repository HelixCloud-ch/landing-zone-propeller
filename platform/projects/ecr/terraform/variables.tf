variable "region" {
  type        = string
  description = "AWS region."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── ECR configuration ─────────────────────────────────────────────────────────

variable "repository_creation_templates" {
  type = map(object({
    description          = optional(string, "")
    image_tag_mutability = optional(string, "IMMUTABLE")
    applied_for          = optional(list(string), ["CREATE_ON_PUSH"])
    encryption_type      = optional(string, "AES256")
    kms_key              = optional(string, null)
    repository_policy    = optional(string, null)
    lifecycle_policy     = optional(string, null)
    resource_tags        = optional(map(string), {})
  }))
  description = "Map of repository creation templates keyed by namespace prefix. Use 'ROOT' for catch-all."
  default = {
    "ROOT" = {}
  }
}

variable "organization_id" {
  type        = string
  description = "AWS Organization ID (e.g. 'o-abc123'). Required for cross-account pull access."
  default     = ""
}

variable "pull_access_ou_ids" {
  type        = list(string)
  description = <<-EOT
    OU IDs to scope pull access (optional). When empty, all accounts in the
    organization can pull. When set, only accounts under these OUs can pull.
    Requires organization_id to be set.

    Example: ["ou-z6og-48q35jmb"]
  EOT
  default     = []
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Per-project tags."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Pipeline-wide tags."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Framework-managed tags."
  default     = {}
}
