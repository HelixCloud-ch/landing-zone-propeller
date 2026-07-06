# ── Transaction Search configuration ─────────────────────────────────────────
#
# Transaction Search is account/region-scoped: enabling it redirects all X-Ray
# trace segment ingestion for the entire account to CloudWatch Logs. There is no
# per-cluster scope; the same setting covers every cluster and every workload
# that sends traces to X-Ray in the account.

variable "enable_transaction_search" {
  type        = bool
  description = "Whether to configure X-Ray trace segment destination to CloudWatch Logs, which enables Transaction Search (the replacement for the X-Ray SDK/Daemon tracing experience). When true, all spans ingested via X-Ray in the account/region are routed to the 'aws/spans' log group and become searchable in CloudWatch Transaction Search and Application Signals."
  default     = true
}

variable "spans_indexing_sampling_percentage" {
  type        = number
  description = "Percentage of trace spans to index as trace summaries in X-Ray (0–100). Indexed spans enable end-to-end trace search and analytics. AWS provides 1% indexing for free; increasing this incurs additional cost. All spans (100%) are stored in the 'aws/spans' log group regardless of this value — only the indexed fraction is used for trace summary analytics. Ignored when enable_transaction_search = false."
  default     = 1

  validation {
    condition     = var.spans_indexing_sampling_percentage >= 0 && var.spans_indexing_sampling_percentage <= 100
    error_message = "spans_indexing_sampling_percentage must be between 0 and 100 inclusive."
  }
}

# ── Resource-based log policy (required for API-based enablement) ─────────────

variable "account_id" {
  type        = string
  description = "AWS account ID. Used in the resource-based policy that authorises X-Ray to write spans to CloudWatch Logs. Required when enable_transaction_search = true."
  default     = null

  validation {
    condition     = !var.enable_transaction_search || (var.account_id != null && length(var.account_id) > 0)
    error_message = "account_id is required when enable_transaction_search = true."
  }
}

variable "region" {
  type        = string
  description = "AWS region. Used in the resource-based policy ARNs for the 'aws/spans' and '/aws/application-signals/data' log groups."
}
