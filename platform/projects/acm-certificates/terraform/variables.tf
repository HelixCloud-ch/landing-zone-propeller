variable "region" {
  type        = string
  description = "AWS region."
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "certificates" {
  type = map(object({
    domain_name               = string
    subject_alternative_names = optional(list(string), [])
    validation_method         = optional(string)
    validation_domains        = optional(map(string), {})
    certificate_authority_arn = optional(string)
    early_renewal_duration    = optional(string)
    key_algorithm             = optional(string)
    wait_for_validation       = optional(bool, false)
    validation_zone_id        = optional(string)
  }))
  description = <<-EOT
    Certificates to request, keyed by a stable id (the terraform state
    address; renaming recreates the certificate). Key: lowercase letters,
    digits, hyphens, at most 32 characters. Per-item rules: see the README.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.certificates) : can(regex("^[a-z0-9-]{1,32}$", k))])
    error_message = "Certificate keys must match ^[a-z0-9-]{1,32}$."
  }
  validation {
    condition = alltrue([
      for c in values(var.certificates) :
      c.validation_zone_id == null || can(regex("^Z[0-9A-Z]{1,32}$", coalesce(c.validation_zone_id, "none")))
    ])
    error_message = "validation_zone_id must be a Route 53 hosted zone ID such as Z0123456789ABCDEFGHIJ."
  }
  validation {
    condition = alltrue([
      for c in values(var.certificates) :
      c.validation_zone_id == null || (c.certificate_authority_arn == null && coalesce(c.validation_method, "DNS") == "DNS")
    ])
    error_message = "validation_zone_id is allowed only with DNS validation (not EMAIL, not a private CA)."
  }
  validation {
    condition = alltrue([
      for c in values(var.certificates) :
      !c.wait_for_validation || c.certificate_authority_arn != null || coalesce(c.validation_method, "DNS") != "DNS" || c.validation_zone_id != null
    ])
    error_message = "wait_for_validation with DNS validation needs validation_zone_id. Set it, or set wait_for_validation = false and publish the records yourself."
  }
  validation {
    condition = alltrue([
      for c in values(var.certificates) :
      !c.wait_for_validation || c.certificate_authority_arn == null
    ])
    error_message = "wait_for_validation must be false with certificate_authority_arn (a private certificate is issued without validation)."
  }
}

variable "validation_timeout" {
  type        = string
  description = "Create timeout of every wait for issuance, like 45m. The pipeline step timeout must be larger."
  default     = "45m"

  validation {
    condition     = can(regex("^[1-9][0-9]*m$", var.validation_timeout))
    error_message = "validation_timeout must be a number of minutes such as 45m."
  }
}

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
