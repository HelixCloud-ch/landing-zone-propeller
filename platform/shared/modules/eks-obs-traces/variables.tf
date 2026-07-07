# ── Cluster identity ──────────────────────────────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Used to derive the default IRSA role name."
}

variable "region" {
  type        = string
  description = "AWS region. Passed to the awsxray exporter so segments are sent to X-Ray in this region."
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
  description = "Name of the IRSA IAM role for the traces collector. Defaults to '<cluster_name>-adot-traces-collector' when null."
  default     = null
}

variable "service_account_name" {
  type        = string
  description = "Name of the Kubernetes ServiceAccount the traces collector assumes via IRSA. Must differ from any other collector in the same namespace."
  default     = "adot-traces-collector"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy the traces collector into. Must be covered by a Fargate profile on pure-Fargate clusters so the collector pod schedules. Defaults to the shared observability namespace used by the metrics collector."
  default     = "fargate-container-insights"
}

# ── Helm chart ────────────────────────────────────────────────────────────────

variable "chart_version" {
  type        = string
  description = "Version of the open-telemetry/opentelemetry-collector Helm chart. Pin to a specific release and bump deliberately. See https://github.com/open-telemetry/opentelemetry-helm-charts/releases."
}

variable "chart_repository" {
  type        = string
  description = "Helm repository for the OpenTelemetry Collector chart. Override to an internal mirror (OCI registry in ECR or an S3-backed Helm repo) in air-gapped environments. Defaults to the upstream open-telemetry Helm charts repository when null."
  default     = null
}

variable "collector_image_repository" {
  type        = string
  description = "Container image repository for the ADOT/OTel Collector. Defaults to the upstream ghcr.io contrib release (the awsxray exporter is an AWS-specific contrib component, so otelcol-k8s is not suitable). Override to an ECR mirror in restricted environments."
  default     = null
}

variable "collector_replicas" {
  type        = number
  description = "Number of collector pod replicas. Increase for HA / higher trace throughput. OTLP is stateless, so replicas scale horizontally behind the Service."
  default     = 1

  validation {
    condition     = var.collector_replicas >= 1
    error_message = "collector_replicas must be at least 1."
  }
}

variable "collector_memory_limit" {
  type        = string
  description = "Kubernetes memory limit for each collector pod."
  default     = "256Mi"
}

variable "collector_cpu_limit" {
  type        = string
  description = "Kubernetes CPU limit for each collector pod."
  default     = "256m"
}
