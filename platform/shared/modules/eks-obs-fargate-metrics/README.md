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
<!-- END_TF_DOCS -->
