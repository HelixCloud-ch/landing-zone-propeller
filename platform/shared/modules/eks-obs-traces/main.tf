# ADOT Collector for trace ingestion — OTLP receiver → AWS X-Ray exporter.
#
# Closes the tracing-ingestion gap: application pods send OpenTelemetry spans
# (OTLP gRPC 4317 / HTTP 4318) to this collector's Service, and the collector
# converts them to X-Ray segments and calls PutTraceSegments. With Transaction
# Search enabled (see the eks-obs-tracing module) those segments land in the
# aws/spans log group and power CloudWatch Application Signals.
#
# This is compute-agnostic (the OTLP receiver works the same on Fargate and
# EC2); on pure-Fargate clusters the pod just needs a Fargate profile covering
# var.namespace. IRSA is used for X-Ray credentials.
#
# Instrumentation is the application's responsibility (OTel SDK, not the X-Ray
# SDK/Daemon which are in maintenance mode). Apps point their OTLP exporter at
# the Service endpoint exposed in the outputs.
#
# References:
#   https://aws-otel.github.io/docs/getting-started/x-ray
#   https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Transaction-Search.html

locals {
  role_name    = coalesce(var.role_name, "${var.cluster_name}-adot-traces-collector")
  release_name = "adot-traces-collector"
  # The opentelemetry-collector chart names its Service <release>-opentelemetry-collector.
  service_name = "${local.release_name}-opentelemetry-collector"

  effective_image_repository = coalesce(
    var.collector_image_repository,
    "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib"
  )
  effective_chart_repository = coalesce(
    var.chart_repository,
    "https://open-telemetry.github.io/opentelemetry-helm-charts"
  )
}

# ── IRSA role ─────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# AWSXRayDaemonWriteAccess grants PutTraceSegments, PutTelemetryRecords and the
# GetSampling* actions the awsxray exporter needs (including remote sampling).
resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ── ADOT Collector Helm release ───────────────────────────────────────────────

resource "helm_release" "adot_traces" {
  name       = local.release_name
  repository = local.effective_chart_repository
  chart      = "opentelemetry-collector"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = true
  cleanup_on_fail  = true

  # image.repository is required since chart 0.89.0; contrib distro carries the
  # awsxray exporter (not in otelcol-k8s). mode=deployment: OTLP is stateless
  # and scales horizontally behind the chart-created Service.
  set = [
    {
      name  = "image.repository"
      value = local.effective_image_repository
    },
    {
      name  = "mode"
      value = "deployment"
    },
    {
      name  = "replicaCount"
      value = tostring(var.collector_replicas)
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
    {
      name  = "resources.limits.memory"
      value = var.collector_memory_limit
    },
    {
      name  = "resources.limits.cpu"
      value = var.collector_cpu_limit
    },
  ]

  set_sensitive = [
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.this.arn
    },
  ]

  values = [
    yamlencode({
      config = yamldecode(templatefile("${path.module}/collector-config.yaml.tpl", {
        region = var.region
      }))
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.xray,
  ]
}
