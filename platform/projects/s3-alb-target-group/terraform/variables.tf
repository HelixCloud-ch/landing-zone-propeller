variable "region" {
  type        = string
  description = "AWS region."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Identity ──────────────────────────────────────────────────────────────────

variable "name" {
  type        = string
  description = "Target group name. Consumers reference the emitted tg_arn from Ingress action annotations, so this name shows up in the AWS console but is not used at request time."
  default     = "s3-static-tg"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.name))
    error_message = "name must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 32 chars (target group name limit)."
  }
}

# ── Pipeline inputs (from workload-vpc / workload-vpc-endpoints outputs) ──────

variable "vpc_id" {
  type        = string
  description = "ID of the workload VPC. Sourced from the workload-vpc project output."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "interface_endpoint_eni_ids" {
  type        = list(string)
  description = "ENI IDs of the S3 interface VPC endpoint. Resolved to private IPs and registered as ALB targets. Wire from workload-vpc-endpoints.interface_network_interface_ids using a pipeline input transform that selects the desired key."

  validation {
    condition     = length(var.interface_endpoint_eni_ids) > 0 && alltrue([for eni in var.interface_endpoint_eni_ids : can(regex("^eni-[0-9a-f]{8,17}$", eni))])
    error_message = "interface_endpoint_eni_ids must be a non-empty list of valid ENI IDs (e.g. eni-0123456789abcdef0)."
  }
}

# ── Health check ──────────────────────────────────────────────────────────────

variable "health_check_matcher" {
  type        = string
  description = "HTTP status codes the ALB health check treats as healthy. Default 307,405 matches S3's response to an ALB health probe without a bucket-identifying Host header."
  default     = "307,405"
}

variable "health_check_interval" {
  type        = number
  description = "Interval between health checks, in seconds."
  default     = 30
}

variable "health_check_timeout" {
  type        = number
  description = "Health check response timeout, in seconds."
  default     = 5
}

variable "healthy_threshold" {
  type        = number
  description = "Consecutive successful health checks required before a target is considered healthy."
  default     = 2
}

variable "unhealthy_threshold" {
  type        = number
  description = "Consecutive failed health checks required before a target is considered unhealthy."
  default     = 2
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
