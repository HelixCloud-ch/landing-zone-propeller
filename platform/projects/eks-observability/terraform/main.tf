# EKS observability — composition project.
#
# Selects the right observability modules for the cluster's compute topology:
#   fargate   → eks-obs-fargate-logs + eks-obs-fargate-metrics
#   nodegroup → eks-obs-cloudwatch-addon (reserved, not yet implemented)
#   mixed     → all of the above (reserved, not yet implemented)
#
# Each module is independently toggled so consumers can install logs-only,
# metrics-only, or neither without changing the project template.
#
# The ADOT Collector (fargate metrics) depends on working in-cluster DNS, so
# if this project is applied on the same run as a fresh CoreDNS rollout, the
# depends_on ensures ordering.

locals {
  is_fargate = contains(["fargate", "mixed"], var.compute_topology)

  # Default log group follows the Container Insights convention.
  effective_log_group = coalesce(
    var.logs_log_group_name,
    "/aws/eks/${var.cluster_name}/application"
  )
}

# ── Fargate: native log router ─────────────────────────────────────────────────

module "fargate_logs" {
  count  = (local.is_fargate && var.install_fargate_logs) ? 1 : 0
  source = "../../../shared/modules/eks-obs-fargate-logs"

  destination                = "cloudwatch"
  log_group_name             = local.effective_log_group
  log_stream_prefix          = var.logs_log_stream_prefix
  log_retention_days         = var.logs_retention_days
  region                     = var.region
  ship_fluentbit_process_logs = var.logs_ship_fluentbit_process_logs
  pod_execution_role_name    = var.pod_execution_role_name
}

# ── Fargate: ADOT Collector metrics ───────────────────────────────────────────

module "fargate_metrics" {
  count  = (local.is_fargate && var.install_fargate_metrics) ? 1 : 0
  source = "../../../shared/modules/eks-obs-fargate-metrics"

  cluster_name              = var.cluster_name
  region                    = var.region
  oidc_provider_arn         = var.oidc_provider_arn
  oidc_provider_url         = var.oidc_provider_url
  namespace                 = var.metrics_collector_namespace
  chart_version             = var.metrics_chart_version
  chart_repository          = var.metrics_chart_repository
  collector_image_repository = var.metrics_image_repository
  collector_replicas        = var.metrics_collector_replicas
  role_name                 = var.metrics_role_name
}

# ── Tracing backend — account/region-scoped ───────────────────────────────────
# Transaction Search is not per-cluster. This module affects all workloads in
# the account that send spans via X-Ray.

module "tracing" {
  count  = var.enable_tracing ? 1 : 0
  source = "../../../shared/modules/eks-obs-tracing"

  enable_transaction_search          = var.enable_tracing
  region                             = var.region
  spans_indexing_sampling_percentage = var.tracing_spans_indexing_percentage
}

# ── Traces collector — OTLP → X-Ray ───────────────────────────────────────────
# Gives apps an in-cluster OTLP endpoint whose spans reach X-Ray / Transaction
# Search. Compute-agnostic; on Fargate the namespace needs a profile.

module "traces_collector" {
  count  = var.install_traces_collector ? 1 : 0
  source = "../../../shared/modules/eks-obs-traces"

  cluster_name               = var.cluster_name
  region                     = var.region
  oidc_provider_arn          = var.oidc_provider_arn
  oidc_provider_url          = var.oidc_provider_url
  namespace                  = var.traces_collector_namespace
  chart_version              = var.traces_chart_version
  chart_repository           = var.traces_chart_repository
  collector_image_repository = var.traces_image_repository
  collector_replicas         = var.traces_collector_replicas
  role_name                  = var.traces_role_name
}
