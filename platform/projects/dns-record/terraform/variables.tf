variable "region" {
  type        = string
  description = "AWS region."
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Record ────────────────────────────────────────────────────────────────────
variable "zone_id" {
  type        = string
  description = "ID of the Route 53 hosted zone that receives the record. The zone must exist in the deployment (target) account."
}

variable "name" {
  type        = string
  description = "Record name, relative to the zone (e.g. 'redis') or fully qualified."
}

variable "type" {
  type        = string
  description = "Record type: A, AAAA, CNAME or TXT. Alias records require A or AAAA."
  default     = "CNAME"
}

variable "ttl" {
  type        = number
  description = "TTL in seconds for non-alias records. Ignored for alias records."
  default     = 300
}

variable "records" {
  type        = list(string)
  description = "Record values for a non-alias record (e.g. an RDS or ElastiCache endpoint). A CNAME takes one value. Set this or alias, not both."
  default     = []
}

variable "alias" {
  type = object({
    name                   = string
    zone_id                = string
    evaluate_target_health = optional(bool, false)
  })
  description = "Alias target (e.g. a load balancer's dns_name and zone_id), for A/AAAA records. Set this or records, not both."
  default     = null
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
