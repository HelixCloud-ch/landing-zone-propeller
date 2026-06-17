# ── Identity ──────────────────────────────────────────────────────────────────

variable "username" {
  type        = string
  description = "IAM user name."

  validation {
    condition     = can(regex("^[\\w+=,.@-]{1,64}$", var.username))
    error_message = "username must be 1–64 characters and contain only alphanumerics and +=,.@- characters."
  }
}

variable "path" {
  type        = string
  description = "IAM path for the user. Must begin and end with '/'."
  default     = "/"

  validation {
    condition     = can(regex("^/.*/$", var.path))
    error_message = "path must begin and end with '/'."
  }
}

# ── Permissions ───────────────────────────────────────────────────────────────

variable "inline_policy_json" {
  type        = string
  description = "JSON-encoded inline policy document to attach to the user. Build it with aws_iam_policy_document in the calling module and pass the result here. Set to null to skip the inline policy entirely."
  default     = null
}

variable "policy_name" {
  type        = string
  description = "Name of the inline policy. Defaults to '<username>-policy' when null. Only used when inline_policy_json is provided."
  default     = null
}

variable "policy_arns" {
  type        = list(string)
  description = "List of managed policy ARNs to attach to the user."
  default     = []
}
