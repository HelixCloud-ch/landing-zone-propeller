# eks-observability

EKS observability composition project. Selects and wires the right
observability modules based on the cluster's compute topology.

## What it deploys

| Module | Topology | Toggle | What it does |
|---|---|---|---|
| `eks-obs-fargate-logs` | `fargate`, `mixed` | `install_fargate_logs` | Native Fargate log router → CloudWatch Logs |
| `eks-obs-fargate-metrics` | `fargate`, `mixed` | `install_fargate_metrics` | ADOT Collector → CloudWatch Container Insights EMF |
| `eks-obs-cloudwatch-addon` | `nodegroup`, `mixed` | *(not yet implemented)* | CloudWatch Observability EKS add-on → Container Insights |

## Fargate log router

Creates the `aws-observability` namespace and the `aws-logging` ConfigMap.
Fargate's built-in Fluent Bit process reads this ConfigMap and routes
container stdout/stderr to the configured destination. No pod is deployed.

**IAM note:** The Fargate pod execution role must have CloudWatch Logs write
permissions. This is NOT managed here — attach the policy to the pod execution
role in the cluster project.

## Fargate ADOT Collector

Deploys an ADOT Collector as a Kubernetes `Deployment` (not a DaemonSet) that
scrapes cAdvisor metrics via the Kubernetes API-server proxy and exports them
to CloudWatch in EMF format. Collects 8 pod-level Container Insights metrics.

Uses **IRSA** — the only supported IAM mechanism on pure-Fargate clusters.

The collector namespace (`metrics_collector_namespace`, default:
`fargate-container-insights`) must be covered by a Fargate profile on the
cluster.

## Pipeline inputs

`cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`,
`oidc_provider_arn`, and `oidc_provider_url` are injected by the pipeline from
the `eks-cluster` step outputs. Do **not** set them in `config.auto.tfvars`.

```yaml
- project: eks-observability
  source: eks-observability
  target: workload-account
  runner: deploy-runner-vpc-app
  depends_on: [eks-addons]
  inputs:
    - name: eks-cluster.cluster_name
      var: cluster_name
    - name: eks-cluster.cluster_endpoint
      var: cluster_endpoint
    - name: eks-cluster.cluster_certificate_authority_data
      var: cluster_certificate_authority_data
    - name: eks-cluster.oidc_provider_arn
      var: oidc_provider_arn
    - name: eks-cluster.oidc_provider_url
      var: oidc_provider_url
```

## What does NOT belong here

- Cluster infrastructure (Fargate profiles, OIDC) — `eks-cluster` project.
- CoreDNS and LB Controller — `eks-addons` project.
- Application traces / OTel SDK instrumentation — app team responsibility.
- Cross-account ECR pull — `eks-ecr-pull` project.

## References

- [ADOT Container Insights on EKS Fargate](https://aws-otel.github.io/docs/getting-started/container-insights/eks-fargate)
- [Fargate logging (native log router)](https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_fargate_logs"></a> [fargate\_logs](#module\_fargate\_logs) | ../../../shared/modules/eks-obs-fargate-logs | n/a |
| <a name="module_fargate_metrics"></a> [fargate\_metrics](#module\_fargate\_metrics) | ../../../shared/modules/eks-obs-fargate-metrics | n/a |
| <a name="module_tracing"></a> [tracing](#module\_tracing) | ../../../shared/modules/eks-obs-tracing | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#input\_cluster\_certificate\_authority\_data) | Base64-encoded certificate authority data for the EKS cluster. Sourced from the eks-cluster project output. Used to configure the kubernetes and helm providers. | `string` | n/a | yes |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | HTTPS endpoint of the EKS API server. Sourced from the eks-cluster project output. Used to configure the kubernetes and helm providers. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Sourced from the eks-cluster project output. Used in metric dimensions and IRSA trust policies. | `string` | n/a | yes |
| <a name="input_compute_topology"></a> [compute\_topology](#input\_compute\_topology) | Compute topology of the cluster. Controls which observability modules are installed. 'fargate' installs the Fargate log router and ADOT metrics collector. 'nodegroup' is reserved for the CloudWatch Observability add-on (not yet implemented). 'mixed' is reserved for future use combining both paths. | `string` | `"fargate"` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_enable_tracing"></a> [enable\_tracing](#input\_enable\_tracing) | Whether to configure the Transaction Search tracing backend. Enables aws\_xray\_trace\_segment\_destination → CloudWatchLogs, the default indexing rule, and the required CloudWatch Logs resource-based policy. Account/region-scoped: affects all workloads sending spans in the account, not only this cluster. | `bool` | `true` | no |
| <a name="input_install_fargate_logs"></a> [install\_fargate\_logs](#input\_install\_fargate\_logs) | Whether to install the native Fargate log router (aws-observability namespace + aws-logging ConfigMap). Applies when compute\_topology = 'fargate'. | `bool` | `true` | no |
| <a name="input_install_fargate_metrics"></a> [install\_fargate\_metrics](#input\_install\_fargate\_metrics) | Whether to install the ADOT Collector for Fargate Container Insights metrics (cAdvisor scrape via API-server proxy → CloudWatch EMF). Applies when compute\_topology = 'fargate'. | `bool` | `true` | no |
| <a name="input_logs_log_group_name"></a> [logs\_log\_group\_name](#input\_logs\_log\_group\_name) | CloudWatch Logs log group for container (application) logs. Convention: '/aws/eks/<cluster\_name>/application'. Required when install\_fargate\_logs = true. | `string` | `null` | no |
| <a name="input_logs_log_stream_prefix"></a> [logs\_log\_stream\_prefix](#input\_logs\_log\_stream\_prefix) | Prefix for CloudWatch Logs log stream names. Each pod's log stream is '<prefix><pod-name>'. | `string` | `"from-fargate-"` | no |
| <a name="input_logs_retention_days"></a> [logs\_retention\_days](#input\_logs\_retention\_days) | CloudWatch Logs retention in days for the application log group. 0 = never expire. | `number` | `30` | no |
| <a name="input_logs_ship_fluentbit_process_logs"></a> [logs\_ship\_fluentbit\_process\_logs](#input\_logs\_ship\_fluentbit\_process\_logs) | Whether to ship Fluent Bit process (internal) logs to CloudWatch. Adds extra cost. Enable only for debugging. | `bool` | `false` | no |
| <a name="input_metrics_chart_repository"></a> [metrics\_chart\_repository](#input\_metrics\_chart\_repository) | Helm repository for the OpenTelemetry Collector chart. Override to an internal mirror in air-gapped environments. Defaults to the upstream open-telemetry Helm charts repository when null. | `string` | `null` | no |
| <a name="input_metrics_chart_version"></a> [metrics\_chart\_version](#input\_metrics\_chart\_version) | Version of the opentelemetry-collector Helm chart. Required when install\_fargate\_metrics = true. See https://github.com/open-telemetry/opentelemetry-helm-charts/releases. | `string` | `null` | no |
| <a name="input_metrics_collector_namespace"></a> [metrics\_collector\_namespace](#input\_metrics\_collector\_namespace) | Kubernetes namespace to deploy the ADOT Collector into. Must be covered by an existing Fargate profile so the collector pod schedules on Fargate. | `string` | `"fargate-container-insights"` | no |
| <a name="input_metrics_collector_replicas"></a> [metrics\_collector\_replicas](#input\_metrics\_collector\_replicas) | Number of ADOT Collector replicas. AWS recommends >1 for clusters with significant load. | `number` | `1` | no |
| <a name="input_metrics_image_repository"></a> [metrics\_image\_repository](#input\_metrics\_image\_repository) | Container image repository for the ADOT Collector. Defaults to the upstream ghcr.io contrib release. Override to an ECR mirror in air-gapped or restricted environments. | `string` | `null` | no |
| <a name="input_metrics_role_name"></a> [metrics\_role\_name](#input\_metrics\_role\_name) | Override for the IRSA role name of the ADOT Collector. Defaults to '<cluster\_name>-adot-collector-metrics' when null. | `string` | `null` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the IAM OIDC provider for the cluster. Sourced from the eks-cluster project output. Required when install\_fargate\_metrics = true (IRSA for the ADOT Collector). | `string` | `null` | no |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | Issuer URL of the OIDC provider, without the https:// prefix. Sourced from the eks-cluster project output. Required when install\_fargate\_metrics = true. | `string` | `null` | no |
| <a name="input_pod_execution_role_name"></a> [pod\_execution\_role\_name](#input\_pod\_execution\_role\_name) | Name of the Fargate pod execution role, sourced from the eks-cluster project output. The native Fargate log router writes to CloudWatch under this role, so the log module attaches the required CloudWatch Logs permissions to it. Required when install\_fargate\_logs = true. | `string` | `null` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the EKS cluster is deployed. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_tracing_spans_indexing_percentage"></a> [tracing\_spans\_indexing\_percentage](#input\_tracing\_spans\_indexing\_percentage) | Percentage of trace spans to index as trace summaries (0–100). 1% is provided free; increasing this incurs cost. All spans are stored in aws/spans regardless of this value. | `number` | `1` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_adot_collector_role_arn"></a> [adot\_collector\_role\_arn](#output\_adot\_collector\_role\_arn) | ARN of the IRSA role for the ADOT Collector. Null when install\_fargate\_metrics = false. |
| <a name="output_adot_collector_role_name"></a> [adot\_collector\_role\_name](#output\_adot\_collector\_role\_name) | Name of the IRSA role for the ADOT Collector. Null when install\_fargate\_metrics = false. |
| <a name="output_fargate_log_group_name"></a> [fargate\_log\_group\_name](#output\_fargate\_log\_group\_name) | CloudWatch Logs log group for container application logs. Null when install\_fargate\_logs = false. |
| <a name="output_metrics_log_group"></a> [metrics\_log\_group](#output\_metrics\_log\_group) | CloudWatch Logs log group for Container Insights EMF performance events. Null when install\_fargate\_metrics = false. |
| <a name="output_spans_log_group_name"></a> [spans\_log\_group\_name](#output\_spans\_log\_group\_name) | CloudWatch Logs log group where X-Ray spans land. Null when tracing is disabled. |
| <a name="output_trace_segment_destination"></a> [trace\_segment\_destination](#output\_trace\_segment\_destination) | X-Ray trace segment destination. 'CloudWatchLogs' when Transaction Search is enabled, null otherwise. |
<!-- END_TF_DOCS -->
