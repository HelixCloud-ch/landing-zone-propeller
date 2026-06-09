# ── Repository creation templates ─────────────────────────────────────────────

variable "repository_creation_templates" {
  type = map(object({
    description          = optional(string, "")
    image_tag_mutability = optional(string, "IMMUTABLE")
    applied_for          = optional(list(string), ["CREATE_ON_PUSH"])
    encryption_type      = optional(string, "AES256")
    kms_key              = optional(string, null)
    custom_role_arn      = optional(string, null)
    repository_policy    = optional(string, null)
    lifecycle_policy     = optional(string, null)
    resource_tags        = optional(map(string), {})
  }))
  description = <<-EOT
    Map of repository creation templates keyed by namespace prefix.
    Use "ROOT" as key for a catch-all template that applies to any repository
    not matching a more specific prefix.

    Example:
      repository_creation_templates = {
        "ROOT" = {}  # catch-all with defaults
        "prod" = { image_tag_mutability = "IMMUTABLE" }
      }
  EOT
  default = {
    "ROOT" = {}
  }
}

variable "default_repository_tags" {
  type        = map(string)
  description = "Tags applied to all repositories created via templates. Merged with per-template resource_tags (per-template wins on conflict)."
  default     = {}
}

# ── Cross-account pull access ─────────────────────────────────────────────────

variable "create_registry_policy" {
  type        = bool
  description = "Whether to create a registry-level policy for cross-account pull access."
  default     = true
}

variable "pull_access_org_paths" {
  type        = list(string)
  description = <<-EOT
    Organization paths to grant pull access. Format:
    "o-<org-id>/r-<root-id>/ou-<ou-id-1>/ou-<ou-id-2>/..."

    Grant to entire org: ["o-abc123/*"]
    Grant to specific OU: ["o-abc123/r-root1/ou-workloads/*"]

    See: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-principalorgpaths
  EOT
  default     = []
}
