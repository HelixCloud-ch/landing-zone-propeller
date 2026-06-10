# ── Repository creation templates ─────────────────────────────────────────────

variable "repository_creation_templates" {
  type = map(object({
    description          = optional(string, "")
    image_tag_mutability = optional(string, "IMMUTABLE_WITH_EXCLUSION")
    image_tag_mutability_exclusion_filters = optional(list(object({
      filter      = string
      filter_type = optional(string, "WILDCARD")
    })), [{ filter = "latest", filter_type = "WILDCARD" }])
    applied_for       = optional(list(string), ["CREATE_ON_PUSH"])
    encryption_type   = optional(string, "AES256")
    kms_key           = optional(string, null)
    repository_policy = optional(string, null)
    lifecycle_policy  = optional(string, null)
    resource_tags     = optional(map(string), {})
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
  description = "Tags applied to all repositories created via templates. Merged with per-template resource_tags."
  default     = {}
}

variable "template_role_name" {
  type        = string
  description = "Name of the IAM role ECR assumes to apply tags/KMS during repository auto-creation."
  default     = "ecr-repository-creation-role"
}

variable "enable_kms_permissions" {
  type        = bool
  description = "Whether to include KMS permissions in the template role (required if any template uses KMS encryption)."
  default     = false
}

# ── Cross-account pull access ─────────────────────────────────────────────────

variable "pull_access_org_paths" {
  type        = list(string)
  description = <<-EOT
    Organization paths to grant pull access. Applied as a repository policy
    to all templates. Format:
    "o-<org-id>/r-<root-id>/ou-<ou-id-1>/ou-<ou-id-2>/..."

    Grant to entire org: ["o-abc123/*"]
    Grant to specific OU: ["o-abc123/r-root1/ou-workloads/*"]

    See: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-principalorgpaths
  EOT
  default     = []
}
