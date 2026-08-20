# ── Secret Identity ───────────────────────────────────────────────────────────
# Exactly one of these four must be set. The presence of each determines
# both the backend (Secrets Manager vs SSM) and the mode (create vs read).

variable "secret_name" {
  type        = string
  description = "Friendly name for a NEW Secrets Manager secret to create."
  default     = null

  validation {
    condition     = length(compact([var.secret_name, var.secret_arn, var.parameter_name, var.parameter_arn])) == 1
    error_message = "Set exactly one of: secret_name, secret_arn, parameter_name, parameter_arn."
  }
}

variable "secret_arn" {
  type        = string
  description = "ARN of an EXISTING Secrets Manager secret to read."
  default     = null

  validation {
    condition     = var.secret_arn == null || can(regex("^arn:aws:secretsmanager:", var.secret_arn))
    error_message = "secret_arn must be a valid Secrets Manager ARN."
  }
}

variable "parameter_name" {
  type        = string
  description = "Full path (starting with /) for a NEW SSM SecureString parameter to create."
  default     = null

  validation {
    condition     = var.parameter_name == null || startswith(var.parameter_name, "/")
    error_message = "parameter_name must start with /."
  }
}

variable "parameter_arn" {
  type        = string
  description = "ARN of an EXISTING SSM parameter to read."
  default     = null

  validation {
    condition     = var.parameter_arn == null || can(regex("^arn:aws:ssm:", var.parameter_arn))
    error_message = "parameter_arn must be a valid SSM parameter ARN."
  }
}

# ── Username Generation ───────────────────────────────────────────────────────

variable "username" {
  type = object({
    prefix              = optional(string, "usr")
    length              = optional(number, 8)
    exclude_characters  = optional(string, "")
    exclude_numbers     = optional(bool, false)
    exclude_lowercase   = optional(bool, false)
    exclude_uppercase   = optional(bool, true)
    exclude_punctuation = optional(bool, true)
    include_space       = optional(bool, false)
  })
  description = <<-EOT
    When set, the stored value becomes JSON {"username":"...","password":"..."}.
    The username is built as prefix concatenated with a random suffix of the
    given length. Defaults produce lowercase alphanumeric suffixes.
    Set to null to store only a plain password string.
  EOT
  default     = null

  validation {
    condition     = var.username == null || can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.username.prefix))
    error_message = "username.prefix must start with a letter and contain only alphanumerics and underscores."
  }

  validation {
    condition     = var.username == null || (var.username.length >= 1 && var.username.length <= 20)
    error_message = "username.length must be between 1 and 20."
  }
}

# ── Password Generation ───────────────────────────────────────────────────────

variable "password" {
  type = object({
    length                     = optional(number, 28)
    exclude_characters         = optional(string, "/@\"\\'\n")
    exclude_lowercase          = optional(bool, false)
    exclude_numbers            = optional(bool, false)
    exclude_punctuation        = optional(bool, false)
    exclude_uppercase          = optional(bool, false)
    include_space              = optional(bool, false)
    require_each_included_type = optional(bool, true)
  })
  description = "Password generation parameters."
  default     = {}
}

# ── Metadata ──────────────────────────────────────────────────────────────────

variable "description" {
  type        = string
  description = "Description for the created secret or parameter."
  default     = null
}

# ── Encryption ────────────────────────────────────────────────────────────────

variable "kms_key_id" {
  type        = string
  description = <<-EOT
    KMS key ARN or alias for encryption. Uses the service default
    key (aws/secretsmanager or aws/ssm) if null.
  EOT
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^(arn:aws:kms:|alias/)", var.kms_key_id))
    error_message = "kms_key_id must be a valid KMS key ARN, alias, or null."
  }
}

# ── Rotation ──────────────────────────────────────────────────────────────────

variable "password_version" {
  type        = number
  description = "Rotation trigger. Bump to generate and store new credentials."
  default     = 1

  validation {
    condition     = var.password_version >= 1
    error_message = "password_version must be >= 1."
  }
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the created resource (create modes only)."
  default     = {}
}
