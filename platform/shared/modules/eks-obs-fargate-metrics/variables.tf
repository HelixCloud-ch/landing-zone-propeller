# ── Cluster identity ──────────────────────────────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Used as a dimension in CloudWatch Container Insights metrics and in the IRSA trust policy."
}

variable "region" {
  type        = string
  description = "AWS region of the cluster. Passed to the ADOT Collector as the CloudWatch EMF exporter region."
}

# ── IRSA ──────────────────────────────────────────────────────────────────────

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster OIDC provider. Used as the IRSA trust principal for the collector's service account role."
}

variable "oidc_provider_url" {
  type        = string
  description = "Issuer URL of the cluster OIDC provider, without the https:// prefix. Used in the IRSA sub/aud trust conditions."
}

variable "role_name" {
  type        = string
  description = "Name of the IRSA IAM role for the ADOT Collector. Defaults to '<cluster_name>-adot-collector-metrics' when null."
  default     = null
}

variable "service_account_name" {
  type        = string
  description = "Name of the Kubernetes ServiceAccount the ADOT Collector assumes via IRSA."
  default     = "adot-collector"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy the ADOT Collector into. Must match an existing Fargate profile namespace so the collector pod schedules on Fargate."
  default     = "fargate-container-insights"
}

# ── Helm chart ────────────────────────────────────────────────────────────────

variable "chart_version" {
  type        = string
  description = "Version of the open-telemetry/opentelemetry-collector Helm chart. Pin to a specific release and bump deliberately. See https://github.com/open-telemetry/opentelemetry-helm-charts/releases."
}

variable "chart_repository" {
  type        = string
  description = "Helm repository for the OpenTelemetry Collector chart."
  default     = "https://open-telemetry.github.io/opentelemetry-helm-charts"
}

variable "collector_replicas" {
  type        = number
  description = "Number of ADOT Collector pod replicas. Use >= 2 on clusters with significant load to avoid a single-collector bottleneck during node replacement. Each replica scrapes all Fargate worker nodes via the API-server proxy independently, so metrics are duplicated — set a dedup strategy if using AMP."
  default     = 1

  validation {
    condition     = var.collector_replicas >= 1
    error_message = "collector_replicas must be at least 1."
  }
}

# ── Collector resource limits ─────────────────────────────────────────────────

variable "collector_memory_limit" {
  type        = string
  description = "Kubernetes memory limit for each ADOT Collector pod. AWS recommends planning for 50–100 MB for the log router; the collector needs more headroom for scraping. Adjust based on cluster size."
  default     = "256Mi"
}

variable "collector_cpu_limit" {
  type        = string
  description = "Kubernetes CPU limit for each ADOT Collector pod."
  default     = "256m"
}
