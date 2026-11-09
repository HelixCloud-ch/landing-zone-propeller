variable "zone_id" {
  type        = string
  description = "ID of the Route 53 hosted zone that receives the record."
}

variable "name" {
  type        = string
  description = "Record name, relative to the zone (e.g. 'redis') or fully qualified."
}

variable "type" {
  type        = string
  description = "Record type: A, AAAA, CNAME or TXT. Alias records require A or AAAA."
  default     = "CNAME"

  validation {
    condition     = contains(["A", "AAAA", "CNAME", "TXT"], var.type)
    error_message = "type must be one of A, AAAA, CNAME, TXT."
  }
}

variable "ttl" {
  type        = number
  description = "TTL in seconds for non-alias records. Ignored for alias records (fixed at 60)."
  default     = 300

  validation {
    condition     = var.ttl >= 0 && var.ttl <= 2147483647
    error_message = "ttl must be between 0 and 2147483647."
  }
}

variable "records" {
  type        = list(string)
  description = "Record values for a non-alias record. A CNAME takes exactly one value."
  default     = []

  validation {
    condition     = var.type != "CNAME" || length(var.records) <= 1
    error_message = "A CNAME record takes exactly one value."
  }
}

variable "alias" {
  type = object({
    name                   = string
    zone_id                = string
    evaluate_target_health = optional(bool, false)
  })
  description = "Alias target (e.g. a load balancer's dns_name and zone_id). Mutually exclusive with records."
  default     = null

  validation {
    condition     = (var.alias == null) != (length(var.records) == 0)
    error_message = "Set exactly one of records or alias."
  }

  validation {
    condition     = var.alias == null || contains(["A", "AAAA"], var.type)
    error_message = "Alias records require type A or AAAA."
  }
}
