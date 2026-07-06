# ── Destination ───────────────────────────────────────────────────────────────

variable "destination" {
  type        = string
  description = "Log destination type. 'cloudwatch' sends container logs to CloudWatch Logs via the cloudwatch_logs Fluent Bit output plugin. Additional destinations ('firehose', 'opensearch') can be added in a later iteration."
  default     = "cloudwatch"

  validation {
    condition     = contains(["cloudwatch"], var.destination)
    error_message = "destination must be 'cloudwatch'."
  }
}

# ── CloudWatch destination (required when destination = "cloudwatch") ──────────

variable "log_group_name" {
  type        = string
  description = "CloudWatch Logs log group name to route container logs into. The log group is created automatically by the cloudwatch_logs plugin (auto_create_group = true). Convention: '/aws/eks/<cluster_name>/application'."
  default     = null

  validation {
    condition     = var.destination != "cloudwatch" || (var.log_group_name != null && length(var.log_group_name) > 0)
    error_message = "log_group_name is required when destination = 'cloudwatch'."
  }
}

variable "log_stream_prefix" {
  type        = string
  description = "Prefix for each CloudWatch Logs log stream. Each stream is named '<prefix><pod-name>'. Convention: 'from-fargate-'."
  default     = "from-fargate-"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention in days for the log group. 0 means never expire. Fargate creates the group on first log delivery; retention is enforced by the plugin."
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value allowed by CloudWatch Logs (0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, or 3653)."
  }
}

variable "region" {
  type        = string
  description = "AWS region of the cluster and the log destination. Required when destination = 'cloudwatch'."
}

# ── Fluent Bit process log shipping (optional, adds cost) ─────────────────────

variable "ship_fluentbit_process_logs" {
  type        = bool
  description = "Whether to ship Fluent Bit process (internal) logs to CloudWatch. Adds extra log ingestion and storage cost. Useful for debugging log routing issues; disable for steady-state environments."
  default     = false
}
