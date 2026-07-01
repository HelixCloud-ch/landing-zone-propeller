variable "account_name" {
  type        = string
  description = "Friendly name for the new account."

  validation {
    condition     = length(var.account_name) > 0 && length(var.account_name) <= 50
    error_message = "account_name must be between 1 and 50 characters."
  }
}

variable "provisioned_product_name" {
  type        = string
  description = <<-EOT
    Name for the Service Catalog provisioned product. Must be unique within the
    management account. The caller (root module) is responsible for uniqueness.
    AWS constraints (ProvisionProduct API):
      - Pattern: [a-zA-Z0-9][a-zA-Z0-9._-]*
      - Maximum length: 128 characters
    Existing provisioned products are unaffected by any name change because
    ignore_changes = [name] is set on the resource.
  EOT

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,126}$", var.provisioned_product_name))
    error_message = "provisioned_product_name must start with [a-zA-Z0-9], contain only [a-zA-Z0-9._-], and be at most 128 characters."
  }
}

variable "account_email" {
  type        = string
  description = "Root email address for the new AWS account. Must be unique across all AWS accounts."
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.account_email))
    error_message = "account_email must be a valid email address."
  }
}

# ── OU placement ─────────────────────────────────────────────────────────────

variable "ou_name" {
  type        = string
  description = <<-EOT
    Name of the Control Tower-registered OU where the account will be placed.
    Combined with ou_id to build the ManagedOrganizationalUnit parameter
    expected by Account Factory ("<ou_name> (<ou_id>)").
  EOT
}

variable "ou_id" {
  type        = string
  description = "ID of the target OU (e.g. ou-abcd-12345678)."

  validation {
    condition     = can(regex("^ou-[0-9a-z]{4,32}-[0-9a-z]{8,32}$", var.ou_id))
    error_message = "ou_id must be a valid OU ID (e.g. ou-abcd-12345678)."
  }
}

variable "sso_user_email" {
  type        = string
  description = "Email for the SSO user that Account Factory creates with AdministratorAccess on the new account."
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.sso_user_email))
    error_message = "sso_user_email must be a valid email address."
  }
}

variable "sso_user_first_name" {
  type        = string
  description = "First name for the SSO user that Account Factory creates."

  validation {
    condition     = length(var.sso_user_first_name) > 0
    error_message = "sso_user_first_name must not be empty."
  }
}

variable "sso_user_last_name" {
  type        = string
  description = "Last name for the SSO user that Account Factory creates."

  validation {
    condition     = length(var.sso_user_last_name) > 0
    error_message = "sso_user_last_name must not be empty."
  }
}

variable "product_name" {
  type        = string
  description = "Name of the Service Catalog product (Control Tower Account Factory by default)."
  default     = "AWS Control Tower Account Factory"
}

variable "portfolio_path_name" {
  type        = string
  description = "Name of the Service Catalog portfolio path that grants access to the product."
  default     = "AWS Control Tower Account Factory Portfolio"
}

variable "provisioning_artifact_name" {
  type        = string
  description = "Name of the provisioning artifact to use. AWS resolves this to the latest active version automatically."
  default     = "AWS Control Tower Account Factory"
}
