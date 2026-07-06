# ADOT Collector for EKS Fargate Container Insights metrics.
#
# On EKS Fargate, pods cannot reach the kubelet directly (the kubelet runs on an
# AWS-managed micro-VM host, not on a shared node). The ADOT Collector works
# around this by scraping cAdvisor metrics through the Kubernetes API-server
# proxy endpoint (/api/v1/nodes/<node>/proxy/metrics/cadvisor), which every
# Fargate pod can reach. A single Collector Deployment can discover all Fargate
# worker nodes via Kubernetes service discovery (role: node).
#
# The collector pipeline:
#   Prometheus receiver (cAdvisor via API-server proxy)
#     → filter processor (drop unwanted metrics)
#     → metrics transform processor (rename/aggregate)
#     → cumulative-to-delta processor (convert cumulative sums)
#     → delta-to-rate processor (convert deltas to rates)
#     → metrics generation processor (derive utilization % metrics)
#     → awsemf exporter (CloudWatch Logs via PutLogEvents in EMF format)
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

  # The collector_config object is the value of the chart's `config:` key.
  # It must be a YAML object, not a string — the chart schema rejects strings.
  # Terraform interpolates var.region and var.cluster_name at plan time;
  # the resulting object is passed to yamlencode which renders it as proper YAML.
  collector_config = {
    receivers = {
      prometheus = {
        config = {
          global = {
            scrape_interval = "60s"
          }
          scrape_configs = [
            {
              job_name             = "kubernetes-pod-resources"
              scheme               = "https"
              metrics_path         = "/metrics/cadvisor"
              bearer_token_file    = "/var/run/secrets/kubernetes.io/serviceaccount/token"
              tls_config = {
                ca_file              = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
                insecure_skip_verify = true
              }
              kubernetes_sd_configs = [{ role = "node" }]
              relabel_configs = [
                {
                  action = "labelmap"
                  regex  = "__meta_kubernetes_node_label_(.+)"
                },
                {
                  source_labels = ["__address__"]
                  action        = "replace"
                  target_label  = "__address__"
                  regex         = "([^:]+)(?::\\d+)?"
                  replacement   = "$1:10250"
                },
                {
                  source_labels = ["__meta_kubernetes_node_label_eks_amazonaws_com_compute_type"]
                  action        = "keep"
                  regex         = "fargate"
                },
              ]
            }
          ]
        }
      }
    }

    processors = {
      filter = {
        metrics = {
          include = {
            match_type   = "regexp"
            metric_names = [
              "container_cpu_usage_seconds_total",
              "container_memory_working_set_bytes",
              "container_network_receive_bytes_total",
              "container_network_transmit_bytes_total",
              "container_spec_cpu_quota",
              "container_spec_memory_limit_bytes",
            ]
          }
        }
      }
      metricstransform = {
        transforms = [
          { include = "container_cpu_usage_seconds_total",      match_type = "strict", action = "update", new_name = "pod_cpu_usage_total" },
          { include = "container_memory_working_set_bytes",     match_type = "strict", action = "update", new_name = "pod_memory_working_set" },
          { include = "container_network_receive_bytes_total",  match_type = "strict", action = "update", new_name = "pod_network_rx_bytes" },
          { include = "container_network_transmit_bytes_total", match_type = "strict", action = "update", new_name = "pod_network_tx_bytes" },
          { include = "container_spec_cpu_quota",               match_type = "strict", action = "update", new_name = "pod_cpu_limit" },
          { include = "container_spec_memory_limit_bytes",      match_type = "strict", action = "update", new_name = "pod_memory_limit" },
        ]
      }
      cumulativetodelta = {
        include = {
          match_type = "strict"
          metrics    = ["pod_cpu_usage_total", "pod_network_rx_bytes", "pod_network_tx_bytes"]
        }
      }
      deltatorate = {
        metrics = ["pod_cpu_usage_total", "pod_network_rx_bytes", "pod_network_tx_bytes"]
      }
      experimental_metricsgeneration = {
        rules = [
          { name = "pod_cpu_utilization_over_pod_limit",    type = "calculate", metric1 = "pod_cpu_usage_total",    metric2 = "pod_cpu_limit",    operation = "percent" },
          { name = "pod_memory_utilization_over_pod_limit", type = "calculate", metric1 = "pod_memory_working_set", metric2 = "pod_memory_limit", operation = "percent" },
        ]
      }
      batch = {}
    }

    exporters = {
      awsemf = {
        region                  = var.region
        log_group_name          = "/aws/containerinsights/${var.cluster_name}/performance"
        log_stream_name         = "fargate"
        namespace               = "ContainerInsights"
        dimension_rollup_option = "NoDimensionRollup"
        metric_declarations = [
          {
            dimensions = [
              ["ClusterName", "LaunchType"],
              ["ClusterName", "Namespace", "LaunchType"],
              ["ClusterName", "Namespace", "PodName", "LaunchType"],
            ]
            metric_name_selectors = [
              "pod_cpu_utilization_over_pod_limit",
              "pod_cpu_usage_total",
              "pod_cpu_limit",
              "pod_memory_utilization_over_pod_limit",
              "pod_memory_working_set",
              "pod_memory_limit",
              "pod_network_rx_bytes",
              "pod_network_tx_bytes",
            ]
          }
        ]
      }
    }

    service = {
      pipelines = {
        metrics = {
          receivers  = ["prometheus"]
          processors = ["filter", "metricstransform", "cumulativetodelta", "deltatorate", "experimental_metricsgeneration", "batch"]
          exporters  = ["awsemf"]
        }
      }
    }
  }
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
  set = [
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

  values = [
    yamlencode({
      config = local.collector_config
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cloudwatch,
  ]
}
