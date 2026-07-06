# ADOT Collector for EKS Fargate Container Insights metrics.
#
# On EKS Fargate, pods cannot reach the kubelet directly (the kubelet runs on an
# AWS-managed micro-VM host, not on a shared node). The ADOT Collector works
# around this by scraping cAdvisor metrics through the Kubernetes API-server
# proxy endpoint (/api/v1/nodes/<node>/proxy/metrics/cadvisor), which every
# Fargate pod can reach. A single Collector Deployment can discover all Fargate
# worker nodes via Kubernetes service discovery (role: node).
#
# The collector pipeline is defined in collector-config.yaml.tpl. Two values are
# interpolated at plan time: region and cluster_name. Everything else is static.
# templatefile() renders the template; yamldecode() parses it into a Terraform
# object; yamlencode() re-serializes it as the Helm chart `config:` value (the
# chart schema requires an object, not a string).
#
# The eight pod metrics emitted to CloudWatch (namespace: ContainerInsights):
#   pod_cpu_utilization_over_pod_limit, pod_cpu_usage_total, pod_cpu_limit,
#   pod_memory_utilization_over_pod_limit, pod_memory_working_set, pod_memory_limit,
#   pod_network_rx_bytes, pod_network_tx_bytes
#
# Dimensions: ClusterName+LaunchType, +Namespace, +Namespace+PodName.
#
# IAM: IRSA is the only supported auth mechanism on Fargate (Pod Identity
# requires the Pod Identity Agent DaemonSet, which cannot run on Fargate).
#
# References:
#   https://aws-otel.github.io/docs/getting-started/container-insights/eks-fargate
#   https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html

locals {
  role_name = coalesce(var.role_name, "${var.cluster_name}-adot-collector-metrics")
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

# CloudWatchAgentServerPolicy grants PutLogEvents + CreateLogGroup/Stream
# which is everything the awsemf exporter needs.
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ── ADOT Collector Helm release ───────────────────────────────────────────────

resource "helm_release" "adot_collector" {
  name       = "adot-collector-fargate-metrics"
  repository = var.chart_repository
  chart      = "opentelemetry-collector"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = true

  # mode=deployment: one or more replicas; not a DaemonSet (which cannot run
  # on Fargate). A single replica scrapes all nodes via the API-server proxy.
  # image.repository is required since chart 0.89.0. We use the contrib distro
  # because otelcol-k8s does not include the awsemf exporter (AWS-specific).
  # Docker Hub was discontinued for this image at 0.122.0; use ghcr.io.
  set = [
    {
      name  = "image.repository"
      value = "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib"
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
      # Inject the IRSA role ARN as a service account annotation so the
      # ADOT Collector pod can assume the role via the OIDC token.
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.this.arn
    },
  ]

  # templatefile renders collector-config.yaml.tpl with region and cluster_name
  # interpolated. yamldecode parses the result into a Terraform object so that
  # yamlencode produces a proper YAML map under the `config` key — the chart
  # schema requires an object, not a string.
  values = [
    yamlencode({
      config = yamldecode(templatefile("${path.module}/collector-config.yaml.tpl", {
        region       = var.region
        cluster_name = var.cluster_name
      }))
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cloudwatch,
  ]
}
