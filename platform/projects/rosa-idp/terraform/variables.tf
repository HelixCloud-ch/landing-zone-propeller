variable "region" {
  type        = string
  description = "AWS region."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Cluster ───────────────────────────────────────────────────────────────────

variable "cluster_id" {
  type        = string
  description = "ROSA cluster ID (from rosa-cluster project output)."
}

variable "cluster_name" {
  type        = string
  description = "ROSA cluster name. Used to derive the default users secret path."
}

# ── IDP ───────────────────────────────────────────────────────────────────────

variable "idp_name" {
  type        = string
  description = "Name of the htpasswd identity provider."
  default     = "htpasswd"
}

variable "users_secret_name" {
  type        = string
  description = "Secrets Manager secret containing the htpasswd users JSON. Format: [{\"username\":\"...\",\"password\":\"...\"}]"
  default     = null
}

# ── Secrets ───────────────────────────────────────────────────────────────────

variable "ocm_secret_name" {
  type        = string
  description = "Name of the Secrets Manager secret containing OCM client_id and client_secret."
  default     = "propeller/rosa/ocm-token"
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  type    = map(string)
  default = {}
}

variable "consumer_tags" {
  type    = map(string)
  default = {}
}

variable "propeller_tags" {
  type    = map(string)
  default = {}
}
