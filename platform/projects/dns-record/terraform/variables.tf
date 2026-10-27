variable "region" {
  type        = string
  description = "AWS region."
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Zone ──────────────────────────────────────────────────────────────────────
variable "zone_id" {
  type        = string
  description = "ID of the Route 53 hosted zone that receives the records. The zone must exist in the deployment (target) account."
}

# ── Records ─────────────────────────────────────────────────────────────────--
variable "records" {
  type = map(object({
    name    = string
    type    = optional(string, "CNAME")
    ttl     = optional(number, 300)
    records = optional(list(string), [])
    alias = optional(object({
      name                   = string
      zone_id                = string
      evaluate_target_health = optional(bool, false)
    }))
  }))
  description = <<-EOT
    Records to publish in the zone, keyed by an arbitrary stable id (the
    terraform state address, not the DNS name). Each entry sets `name` plus
    exactly one of `records` (non-alias, e.g. a CNAME to a service endpoint)
    or `alias` (A/AAAA to a load balancer); the module enforces that.

    To wire a single value from the pipeline into an entry's one-element
    `records` list, use a JSONata input transform: `expr: '[$]'`.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for r in var.records : (r.alias == null) != (length(r.records) == 0)])
    error_message = "Each record must set exactly one of records or alias."
  }
}

# ── Tags ──────────────────────────────────────────────────────────────────────
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
