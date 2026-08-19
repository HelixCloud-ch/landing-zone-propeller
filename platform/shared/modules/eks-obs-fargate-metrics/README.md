# eks-obs-fargate-metrics

ADOT Collector for EKS Fargate Container Insights metrics. Deploys a
Kubernetes `Deployment` (not a DaemonSet) that scrapes cAdvisor metrics via the
Kubernetes API-server proxy and exports them to CloudWatch in embedded metric
format (EMF).

## Why a Deployment, not a DaemonSet

On EKS Fargate there are no shared EC2 nodes, so DaemonSets cannot schedule.
The Fargate networking model also prevents a pod from reaching the kubelet
directly. The ADOT Collector works around this by targeting
`/metrics/cadvisor` via the Kubernetes API-server proxy
(`/api/v1/nodes/<node>/proxy/metrics/cadvisor`), which every pod with the
right RBAC can reach. A single Collector instance can discover all Fargate
worker nodes via Kubernetes service discovery (`role: node`).

## Metrics emitted (CloudWatch namespace: ContainerInsights)

Eight pod-level metrics:

| Metric | Description |
|---|---|
| `pod_cpu_usage_total` | Pod CPU usage (rate) |
| `pod_cpu_limit` | CPU limit from container spec |
| `pod_cpu_utilization_over_pod_limit` | CPU usage / limit % |
| `pod_memory_working_set` | Pod memory working set (bytes) |
| `pod_memory_limit` | Memory limit from container spec |
| `pod_memory_utilization_over_pod_limit` | Memory working set / limit % |
| `pod_network_rx_bytes` | Network receive rate (bytes/s) |
| `pod_network_tx_bytes` | Network transmit rate (bytes/s) |

Dimensions: `ClusterName+LaunchType`, `+Namespace`, `+Namespace+PodName`.

## IAM

Uses **IRSA** (the only supported mechanism on Fargate — Pod Identity requires
the Pod Identity Agent DaemonSet, which cannot run on Fargate). The module
creates an IAM role with the `CloudWatchAgentServerPolicy` managed policy
attached and annotates the collector ServiceAccount with the role ARN.

## Fargate profile requirement

The collector pod runs in `var.namespace` (default: `fargate-container-insights`).
That namespace must be covered by a Fargate profile on the cluster, otherwise
the pod stays `Pending`.

## Helm chart

The module uses the `opentelemetry-collector` chart from
`https://open-telemetry.github.io/opentelemetry-helm-charts`. Pin
`chart_version` and bump deliberately.

## What does NOT belong here

- Node-level metrics (host CPU, disk) — not available on Fargate.
- Application traces / spans — use `eks-obs-tracing` (future).
- Container logs — use `eks-obs-fargate-logs`.

## References

- [ADOT Container Insights on EKS Fargate](https://aws-otel.github.io/docs/getting-started/container-insights/eks-fargate)
- [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [OpenTelemetry Helm Charts](https://github.com/open-telemetry/opentelemetry-helm-charts/releases)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [helm_release.adot_collector](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | Helm repository for the OpenTelemetry Collector chart. Override to an internal mirror (e.g. an OCI registry in ECR or an S3-backed Helm repo) in air-gapped or restricted environments. Defaults to the upstream open-telemetry Helm charts repository when null. | `string` | `null` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the open-telemetry/opentelemetry-collector Helm chart. Pin to a specific release and bump deliberately. See https://github.com/open-telemetry/opentelemetry-helm-charts/releases. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Used as a dimension in CloudWatch Container Insights metrics and in the IRSA trust policy. | `string` | n/a | yes |
| <a name="input_collector_cpu_limit"></a> [collector\_cpu\_limit](#input\_collector\_cpu\_limit) | Kubernetes CPU limit for each ADOT Collector pod. | `string` | `"256m"` | no |
| <a name="input_collector_image_repository"></a> [collector\_image\_repository](#input\_collector\_image\_repository) | Container image repository for the ADOT Collector. Defaults to the upstream ghcr.io contrib release. Override to an ECR mirror (e.g. '<account>.dkr.ecr.<region>.amazonaws.com/opentelemetry-collector-contrib') when pulling from public registries is restricted. Must include the awsemf exporter — otelcol-k8s is not suitable. | `string` | `null` | no |
| <a name="input_collector_memory_limit"></a> [collector\_memory\_limit](#input\_collector\_memory\_limit) | Kubernetes memory limit for each ADOT Collector pod. AWS recommends planning for 50–100 MB for the log router; the collector needs more headroom for scraping. Adjust based on cluster size. | `string` | `"256Mi"` | no |
| <a name="input_collector_replicas"></a> [collector\_replicas](#input\_collector\_replicas) | Number of ADOT Collector pod replicas. Use >= 2 on clusters with significant load to avoid a single-collector bottleneck during node replacement. Each replica scrapes all Fargate worker nodes via the API-server proxy independently, so metrics are duplicated — set a dedup strategy if using AMP. | `number` | `1` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to deploy the ADOT Collector into. Must match an existing Fargate profile namespace so the collector pod schedules on Fargate. | `string` | `"fargate-container-insights"` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the cluster OIDC provider. Used as the IRSA trust principal for the collector's service account role. | `string` | n/a | yes |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | Issuer URL of the cluster OIDC provider, without the https:// prefix. Used in the IRSA sub/aud trust conditions. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster. Passed to the ADOT Collector as the CloudWatch EMF exporter region. | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IRSA IAM role for the ADOT Collector. Defaults to '<cluster\_name>-adot-collector-metrics' when null. | `string` | `null` | no |
| <a name="input_service_account_name"></a> [service\_account\_name](#input\_service\_account\_name) | Name of the Kubernetes ServiceAccount the ADOT Collector assumes via IRSA. | `string` | `"adot-collector"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloudwatch_log_group"></a> [cloudwatch\_log\_group](#output\_cloudwatch\_log\_group) | CloudWatch Logs log group where Container Insights performance EMF events are written. |
| <a name="output_collector_namespace"></a> [collector\_namespace](#output\_collector\_namespace) | Kubernetes namespace the ADOT Collector is deployed into. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IRSA role assumed by the ADOT Collector service account. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the IRSA role assumed by the ADOT Collector service account. |
<!-- END_TF_DOCS -->
