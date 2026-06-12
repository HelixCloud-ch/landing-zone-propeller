variable "region" {
  type        = string
  description = "AWS region (must match the IAM Identity Center home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Identity source ──────────────────────────────────────────────────────────
# When external_idp = false (default), the IdentityOperators group is created
# locally in the IAM Identity Center identity store and IdentityOperators have
# full directory admin (so they can create the other base groups).
#
# When external_idp = true, the IdentityOperators group is expected to be
# provisioned by an external IdP (e.g. Entra ID via SCIM) and is looked up
# by name. IdentityOperators get directory read-only — writes would conflict
# with SCIM sync.
#
# AWS does not expose the identity source in any describe/list API, so we
# rely on this explicit flag rather than autodetection.

variable "external_idp" {
  type        = bool
  description = "Whether IAM Identity Center is fed by an external IdP via SCIM. When true, the IdentityOperators group is looked up instead of created."
  default     = false
}

# ── Group name ───────────────────────────────────────────────────────────────

variable "identity_operators_group_name" {
  type        = string
  description = "Name of the IdentityOperators group. The other base groups (aws-admins, aws-powerusers, aws-readonly-users) are created by IdentityOperators members at runtime, not by this project."
  default     = "aws-identity-operators"
}

# ── Permission set behavior ──────────────────────────────────────────────────

variable "relay_states" {
  type = object({
    readonly          = optional(string, "")
    poweruser         = optional(string, "")
    admin             = optional(string, "")
    identity_operator = optional(string, "")
  })
  description = <<-EOT
    Per-permission-set relay state URL overrides. Each key is optional; omit
    or leave empty to use the built-in default for that permission set.

    Defaults (computed from var.region):
      readonly, poweruser, admin  -> https://<region>.console.aws.amazon.com
      identity_operator           -> https://<region>.console.aws.amazon.com/singlesignon/

    Override example - send Admin users to the CloudTrail console:
      relay_states = {
        admin = "https://eu-central-2.console.aws.amazon.com/cloudtrail/"
      }

    See: https://docs.aws.amazon.com/singlesignon/latest/userguide/howtopermrelaystate.html
  EOT
  default     = {}

  validation {
    condition = alltrue([
      for v in compact([
        var.relay_states.readonly,
        var.relay_states.poweruser,
        var.relay_states.admin,
        var.relay_states.identity_operator,
      ]) : can(regex("^https://", v))
    ])
    error_message = "All relay_states values must be valid HTTPS URLs."
  }
}

variable "session_duration" {
  type        = string
  description = "Session duration for all permission sets (ISO 8601, e.g. PT1H, PT8H)."
  default     = "PT1H"

  validation {
    condition     = can(regex("^PT([0-9]+H)?([0-9]+M)?$", var.session_duration))
    error_message = "session_duration must be an ISO 8601 duration (e.g. PT1H, PT8H, PT30M)."
  }
}

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
