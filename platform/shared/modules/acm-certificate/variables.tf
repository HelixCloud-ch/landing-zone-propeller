variable "domain_name" {
  type        = string
  description = "Primary domain name. May start with `*.`. At most 64 characters."

  validation {
    condition = (
      can(regex("^(\\*\\.)?([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", var.domain_name))
      && length(var.domain_name) <= 64
    )
    error_message = "domain_name must be a valid domain name (optional '*.' prefix, labels of 1-63 characters) of at most 64 characters."
  }
}

variable "subject_alternative_names" {
  type        = list(string)
  description = "Additional domain names on the certificate. At most 99 (ACM hard limit)."
  default     = []

  validation {
    condition = alltrue([
      for s in var.subject_alternative_names :
      can(regex("^(\\*\\.)?([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", s)) && length(s) <= 253
    ])
    error_message = "Each subject alternative name must be a valid domain name (optional '*.' prefix) of at most 253 characters."
  }

  validation {
    condition     = length(var.subject_alternative_names) <= 99
    error_message = "At most 99 subject alternative names are allowed (100 names with the primary name). The default account quota is lower; ACM reports it at apply."
  }

  validation {
    condition = (
      !contains(var.subject_alternative_names, var.domain_name)
      && length(distinct(var.subject_alternative_names)) == length(var.subject_alternative_names)
    )
    error_message = "subject_alternative_names must not repeat domain_name or contain duplicates. ACM adds domain_name itself."
  }
}

variable "validation_method" {
  type        = string
  description = "DNS or EMAIL. Null means DNS, or no validation with a private CA."
  default     = null

  validation {
    condition     = var.validation_method == null || contains(["DNS", "EMAIL"], coalesce(var.validation_method, "none"))
    error_message = "validation_method must be null, DNS, or EMAIL."
  }

  validation {
    condition     = var.validation_method == null || var.certificate_authority_arn == null
    error_message = "validation_method must be null when certificate_authority_arn is set."
  }
}

variable "validation_domains" {
  type        = map(string)
  description = "EMAIL only. Maps a certificate name to its validation domain (the name or a parent)."
  default     = {}

  validation {
    condition     = length(var.validation_domains) == 0 || var.validation_method == "EMAIL"
    error_message = "validation_domains is allowed only with validation_method = \"EMAIL\"."
  }

  validation {
    condition = alltrue([
      for k, v in var.validation_domains :
      contains(concat([var.domain_name], var.subject_alternative_names), k) && (k == v || endswith(k, ".${v}"))
    ])
    error_message = "Each validation_domains key must be domain_name or a SAN, and its value must be that name or a parent domain of it."
  }
}

variable "certificate_authority_arn" {
  type        = string
  description = "ARN of an AWS Private CA. Set it to request a private certificate."
  default     = null

  validation {
    condition     = var.certificate_authority_arn == null || can(regex("^arn:aws[a-z-]*:acm-pca:[a-z0-9-]+:[0-9]{12}:certificate-authority/.+$", coalesce(var.certificate_authority_arn, "none")))
    error_message = "certificate_authority_arn must be null or an AWS Private CA ARN."
  }
}

variable "early_renewal_duration" {
  type        = string
  description = "Private CA only. How early ACM renews the certificate, for example P90D or 2160h."
  default     = null

  validation {
    condition     = var.early_renewal_duration == null || can(regex("^(P[0-9]+D|[0-9]+h)$", coalesce(var.early_renewal_duration, "none")))
    error_message = "early_renewal_duration must be null, a day count such as P90D, or an hour count such as 2160h."
  }

  validation {
    condition     = var.early_renewal_duration == null || var.certificate_authority_arn != null
    error_message = "early_renewal_duration is allowed only with certificate_authority_arn."
  }
}

variable "key_algorithm" {
  type        = string
  description = "Key algorithm. Null uses the ACM default (RSA_2048)."
  default     = null

  validation {
    condition     = var.key_algorithm == null || contains(["RSA_2048", "EC_prime256v1", "EC_secp384r1"], coalesce(var.key_algorithm, "none"))
    error_message = "key_algorithm must be null, RSA_2048, EC_prime256v1, or EC_secp384r1."
  }
}

variable "wait_for_validation" {
  type        = bool
  description = "Wait until the certificate is ISSUED. Not allowed with a private CA."
  default     = false

  validation {
    condition     = !var.wait_for_validation || var.certificate_authority_arn == null
    error_message = "wait_for_validation must be false with certificate_authority_arn (a private certificate is issued without validation)."
  }
}

variable "validation_record_fqdns" {
  type        = list(string)
  description = "DNS with wait_for_validation only. Record names the provider checks before it waits."
  default     = []

  validation {
    condition = (
      length(var.validation_record_fqdns) == 0
      || (var.wait_for_validation && var.certificate_authority_arn == null && coalesce(var.validation_method, "DNS") == "DNS")
    )
    error_message = "validation_record_fqdns is allowed only with DNS validation and wait_for_validation = true."
  }
}

variable "validation_timeout" {
  type        = string
  description = "Create timeout of the wait, in minutes (for example 45m)."
  default     = "45m"

  validation {
    condition     = can(regex("^[1-9][0-9]*m$", var.validation_timeout))
    error_message = "validation_timeout must be a number of minutes such as 45m."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags for the certificate. A Name tag with the domain name is added; a caller Name wins."
  default     = {}
}
