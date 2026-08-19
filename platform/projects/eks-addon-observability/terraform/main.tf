# EKS observability — composition project.
#
# Selects the right observability modules for the cluster's compute topology:
#   fargate   → eks-obs-fargate-logs + eks-obs-fargate-metrics
#   nodegroup → eks-obs-cloudwatch-addon (CloudWatch Observability EKS add-on)
#   mixed     → all of the above
#
# Each module is independently toggled so consumers can install logs-only,
# metrics-only, or neither without changing the project template.
#
# The ADOT Collector (fargate metrics) depends on working in-cluster DNS, so
# if this project is applied on the same run as a fresh CoreDNS rollout, the
# depends_on ensures ordering.

locals {
  is_fargate   = contains(["fargate", "mixed"], var.compute_topology)
  is_nodegroup = contains(["nodegroup", "mixed"], var.compute_topology)

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

  destination                 = "cloudwatch"
  log_group_name              = local.effective_log_group
  log_stream_prefix           = var.logs_log_stream_prefix
  log_retention_days          = var.logs_retention_days
  region                      = var.region
  ship_fluentbit_process_logs = var.logs_ship_fluentbit_process_logs
  pod_execution_role_name     = var.pod_execution_role_name
}

# ── Fargate: ADOT Collector metrics ───────────────────────────────────────────

module "fargate_metrics" {
  count  = (local.is_fargate && var.install_fargate_metrics) ? 1 : 0
  source = "../../../shared/modules/eks-obs-fargate-metrics"

  cluster_name               = var.cluster_name
  region                     = var.region
  oidc_provider_arn          = var.oidc_provider_arn
  oidc_provider_url          = var.oidc_provider_url
  namespace                  = var.metrics_collector_namespace
  chart_version              = var.metrics_chart_version
  chart_repository           = var.metrics_chart_repository
  collector_image_repository = var.metrics_image_repository
  collector_replicas         = var.metrics_collector_replicas
  role_name                  = var.metrics_role_name
}

# ── EC2 node groups: CloudWatch Observability EKS add-on ──────────────────────
# Deploys the CloudWatch Agent + Fluent Bit DaemonSets via the managed add-on.
# Container Insights enhanced observability + Application Signals + container
# log shipping are all handled by this single add-on.
#
# The IRSA role is created here (project owns orchestration) and passed to the
# generic eks-addon-base module which manages the add-on lifecycle.

locals {
  cw_obs_role_name = coalesce(
    var.cloudwatch_observability_role_name,
    "${var.cluster_name}-aws-cloudwatch-observability-addon"
  )
  install_cw_obs = local.is_nodegroup && var.install_cloudwatch_observability

  # Accept the add-on's configuration_values from a JSON or YAML file (the
  # shapes AWS's own `describe-addon-configuration` docs use) so consumers
  # don't have to hand-convert an existing config into a JSON string.
  # yamldecode() parses both YAML and JSON (JSON is a YAML subset), so the
  # file's format is inferred from its extension, not re-implemented here.
  # Gated by install_cw_obs so the file() read is skipped entirely — not just
  # its result discarded — when the add-on isn't installed (e.g. Fargate-only
  # clusters). Otherwise a stale or not-yet-created path fails plan even when
  # this value would never be used.
  cw_obs_configuration_values_from_file = (
    local.install_cw_obs && var.cloudwatch_observability_configuration_values_file != null
    ? jsonencode(yamldecode(file("${path.module}/${var.cloudwatch_observability_configuration_values_file}")))
    : null
  )

  cw_obs_configuration_values = (
    local.cw_obs_configuration_values_from_file != null
    ? local.cw_obs_configuration_values_from_file
    : var.cloudwatch_observability_configuration_values
  )
}

data "aws_iam_policy_document" "cw_obs_assume" {
  count = local.install_cw_obs ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringLike"
      variable = "${var.oidc_provider_url}:sub"
      values = [
        "system:serviceaccount:amazon-cloudwatch:amazon-cloudwatch-observability-controller-manager",
        "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent",
      ]
    }
  }
}

resource "aws_iam_role" "cw_obs" {
  count = local.install_cw_obs ? 1 : 0

  name               = local.cw_obs_role_name
  assume_role_policy = data.aws_iam_policy_document.cw_obs_assume[0].json
}

resource "aws_iam_role_policy_attachment" "cw_obs_cloudwatch_agent" {
  count = local.install_cw_obs ? 1 : 0

  role       = aws_iam_role.cw_obs[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "cw_obs_xray_write" {
  count = local.install_cw_obs ? 1 : 0

  role       = aws_iam_role.cw_obs[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

module "cloudwatch_observability" {
  count  = local.install_cw_obs ? 1 : 0
  source = "../../../shared/modules/eks-addon-base"

  cluster_name             = var.cluster_name
  addon_name               = "amazon-cloudwatch-observability"
  addon_version            = var.cloudwatch_observability_version
  configuration_values     = local.cw_obs_configuration_values
  service_account_role_arn = aws_iam_role.cw_obs[0].arn

  depends_on = [
    aws_iam_role_policy_attachment.cw_obs_cloudwatch_agent,
    aws_iam_role_policy_attachment.cw_obs_xray_write,
  ]
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
