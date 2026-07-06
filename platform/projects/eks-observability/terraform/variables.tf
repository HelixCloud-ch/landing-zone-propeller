# ── Region ────────────────────────────────────────────────────────────────────

variable "region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed."
}

# ── Pipeline inputs (injected from upstream project outputs) ──────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Sourced from the eks-cluster project output. Used in metric dimensions and IRSA trust policies."
}

variable "cluster_endpoint" {
  type        = string
  description = "HTTPS endpoint of the EKS API server. Sourced from the eks-cluster project output. Used to configure the kubernetes and helm providers."
}

variable "cluster_certificate_authority_data" {
  type        = string
  description = "Base64-encoded certificate authority data for the EKS cluster. Sourced from the eks-cluster project output. Used to configure the kubernetes and helm providers."
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the IAM OIDC provider for the cluster. Sourced from the eks-cluster project output. Required when install_fargate_metrics = true (IRSA for the ADOT Collector)."
  default     = null
}

variable "oidc_provider_url" {
  type        = string
  description = "Issuer URL of the OIDC provider, without the https:// prefix. Sourced from the eks-cluster project output. Required when install_fargate_metrics = true."
  default     = null
}

# ── Compute topology ──────────────────────────────────────────────────────────

variable "compute_topology" {
  type        = string
  description = "Compute topology of the cluster. Controls which observability modules are installed. 'fargate' installs the Fargate log router and ADOT metrics collector. 'nodegroup' is reserved for the CloudWatch Observability add-on (not yet implemented). 'mixed' is reserved for future use combining both paths."
  default     = "fargate"

  validation {
    condition     = contains(["fargate", "nodegroup", "mixed"], var.compute_topology)
    error_message = "compute_topology must be 'fargate', 'nodegroup', or 'mixed'. 'nodegroup' and 'mixed' are reserved for future use."
  }
}

# ── Fargate log router (eks-obs-fargate-logs) ─────────────────────────────────

variable "install_fargate_logs" {
  type        = bool
  description = "Whether to install the native Fargate log router (aws-observability namespace + aws-logging ConfigMap). Applies when compute_topology = 'fargate'."
  default     = true
}

variable "logs_log_group_name" {
  type        = string
  description = "CloudWatch Logs log group for container (application) logs. Convention: '/aws/eks/<cluster_name>/application'. Required when install_fargate_logs = true."
  default     = null
}

variable "logs_log_stream_prefix" {
  type        = string
  description = "Prefix for CloudWatch Logs log stream names. Each pod's log stream is '<prefix><pod-name>'."
  default     = "from-fargate-"
}

variable "logs_retention_days" {
  type        = number
  description = "CloudWatch Logs retention in days for the application log group. 0 = never expire."
  default     = 30
}

variable "logs_ship_fluentbit_process_logs" {
  type        = bool
  description = "Whether to ship Fluent Bit process (internal) logs to CloudWatch. Adds extra cost. Enable only for debugging."
  default     = false
}

# ── Fargate ADOT metrics collector (eks-obs-fargate-metrics) ──────────────────

variable "install_fargate_metrics" {
  type        = bool
  description = "Whether to install the ADOT Collector for Fargate Container Insights metrics (cAdvisor scrape via API-server proxy → CloudWatch EMF). Applies when compute_topology = 'fargate'."
  default     = true
}

variable "metrics_collector_namespace" {
  type        = string
  description = "Kubernetes namespace to deploy the ADOT Collector into. Must be covered by an existing Fargate profile so the collector pod schedules on Fargate."
  default     = "fargate-container-insights"
}

variable "metrics_chart_version" {
  type        = string
  description = "Version of the opentelemetry-collector Helm chart. Required when install_fargate_metrics = true. See https://github.com/open-telemetry/opentelemetry-helm-charts/releases."
  default     = null
}

variable "metrics_chart_repository" {
  type        = string
  description = "Helm repository for the OpenTelemetry Collector chart. Override to an internal mirror in air-gapped environments. Defaults to the upstream open-telemetry Helm charts repository when null."
  default     = null
}

variable "metrics_collector_replicas" {
  type        = number
  description = "Number of ADOT Collector replicas. AWS recommends >1 for clusters with significant load."
  default     = 1
}

variable "metrics_role_name" {
  type        = string
  description = "Override for the IRSA role name of the ADOT Collector. Defaults to '<cluster_name>-adot-collector-metrics' when null."
  default     = null
}

variable "metrics_image_repository" {
  type        = string
  description = "Container image repository for the ADOT Collector. Defaults to the upstream ghcr.io contrib release. Override to an ECR mirror in air-gapped or restricted environments."
  default     = null
}

# ── Tracing backend (eks-obs-tracing) — account/region-scoped ────────────────

variable "enable_tracing" {
  type        = bool
  description = "Whether to configure the Transaction Search tracing backend. Enables aws_xray_trace_segment_destination → CloudWatchLogs, the default indexing rule, and the required CloudWatch Logs resource-based policy. Account/region-scoped: affects all workloads sending spans in the account, not only this cluster."
  default     = true
}

variable "tracing_spans_indexing_percentage" {
  type        = number
  description = "Percentage of trace spans to index as trace summaries (0–100). 1% is provided free; increasing this incurs cost. All spans are stored in aws/spans regardless of this value."
  default     = 1
}

# ── Tagging ────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Base tags merged into the provider default_tags block."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Consumer-specific tags merged into the provider default_tags block."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Propeller framework tags merged into the provider default_tags block."
  default     = {}
}
