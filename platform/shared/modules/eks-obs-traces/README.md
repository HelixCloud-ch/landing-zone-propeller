# eks-obs-traces

ADOT Collector for trace ingestion — an OTLP receiver that exports to AWS X-Ray.
Closes the tracing-ingestion gap: it gives application pods an in-cluster
endpoint to send OpenTelemetry spans to, and forwards them to X-Ray /
CloudWatch Transaction Search.

## Pipeline

```
app (OTel SDK) --OTLP--> this collector (Service :4317/:4318)
                           → memory_limiter → batch → awsxray exporter
                           → PutTraceSegments → X-Ray
                           → (Transaction Search enabled) → aws/spans log group
```

The `awsxray` exporter converts OTLP spans to X-Ray segment format and calls
`PutTraceSegments`. It uses IRSA credentials (managed policy
`AWSXRayDaemonWriteAccess`, which also covers X-Ray remote sampling). This is
the AWS-documented ADOT-on-EKS path and reuses the same X-Ray → `aws/spans`
route we validated for the backend.

## How applications use it

Instrumentation is the **application's** responsibility (OTel SDK — not the
X-Ray SDK/Daemon, which are in maintenance mode since 2026-02-25). Apps set:

```
OTEL_EXPORTER_OTLP_ENDPOINT = http://<otlp_http_endpoint>   # from module output
OTEL_SERVICE_NAME           = <your-service>
```

The module outputs `otlp_grpc_endpoint` (:4317) and `otlp_http_endpoint`
(:4318) — the in-cluster Service DNS names to point the SDK at.

## Compute

Compute-agnostic — the OTLP receiver behaves the same on Fargate and EC2
(unlike the metrics collector, which needs the Fargate API-server-proxy scrape).
On a pure-Fargate cluster the pod still needs a Fargate profile covering
`var.namespace`; it defaults to the shared `fargate-container-insights`
namespace, which already has a profile alongside the metrics collector. Its
ServiceAccount name is distinct (`adot-traces-collector`) so the two collectors
coexist.

## Alternative: CloudWatch OTLP endpoint

AWS also offers a native OTLP trace endpoint
(`https://xray.<region>.amazonaws.com/v1/traces`, SigV4-signed) usable via the
collector's `otlphttp` exporter plus the `sigv4auth` extension. This module uses
the `awsxray` exporter instead — simpler (no extension), proven, and identical
destination (`aws/spans`). Switching to the OTLP endpoint is a future option if
we standardize on native-OTLP ingestion.

## What does NOT belong here

- The Transaction Search backend enablement — that is `eks-obs-tracing`
  (account/region-scoped). This module assumes it is enabled.
- Application instrumentation — owned by app teams.
- Metrics/logs — separate modules.

## References

- [AWS X-Ray Exporter in the Collector](https://aws-otel.github.io/docs/getting-started/x-ray)
- [CloudWatch Transaction Search](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Transaction-Search.html)
- [X-Ray SDKs/Daemon → OpenTelemetry migration](https://aws.amazon.com/blogs/mt/aws-x-ray-sdks-daemon-migration-to-opentelemetry/)

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
| [aws_iam_role_policy_attachment.xray](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [helm_release.adot_traces](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | Helm repository for the OpenTelemetry Collector chart. Override to an internal mirror (OCI registry in ECR or an S3-backed Helm repo) in air-gapped environments. Defaults to the upstream open-telemetry Helm charts repository when null. | `string` | `null` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the open-telemetry/opentelemetry-collector Helm chart. Pin to a specific release and bump deliberately. See https://github.com/open-telemetry/opentelemetry-helm-charts/releases. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Used to derive the default IRSA role name. | `string` | n/a | yes |
| <a name="input_collector_cpu_limit"></a> [collector\_cpu\_limit](#input\_collector\_cpu\_limit) | Kubernetes CPU limit for each collector pod. | `string` | `"256m"` | no |
| <a name="input_collector_image_repository"></a> [collector\_image\_repository](#input\_collector\_image\_repository) | Container image repository for the ADOT/OTel Collector. Defaults to the upstream ghcr.io contrib release (the awsxray exporter is an AWS-specific contrib component, so otelcol-k8s is not suitable). Override to an ECR mirror in restricted environments. | `string` | `null` | no |
| <a name="input_collector_memory_limit"></a> [collector\_memory\_limit](#input\_collector\_memory\_limit) | Kubernetes memory limit for each collector pod. | `string` | `"256Mi"` | no |
| <a name="input_collector_replicas"></a> [collector\_replicas](#input\_collector\_replicas) | Number of collector pod replicas. Increase for HA / higher trace throughput. OTLP is stateless, so replicas scale horizontally behind the Service. | `number` | `1` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to deploy the traces collector into. Must be covered by a Fargate profile on pure-Fargate clusters so the collector pod schedules. Defaults to the shared observability namespace used by the metrics collector. | `string` | `"fargate-container-insights"` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the cluster OIDC provider. Used as the IRSA trust principal for the collector's service account role. | `string` | n/a | yes |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | Issuer URL of the cluster OIDC provider, without the https:// prefix. Used in the IRSA sub/aud trust conditions. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region. Passed to the awsxray exporter so segments are sent to X-Ray in this region. | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IRSA IAM role for the traces collector. Defaults to '<cluster\_name>-adot-traces-collector' when null. | `string` | `null` | no |
| <a name="input_service_account_name"></a> [service\_account\_name](#input\_service\_account\_name) | Name of the Kubernetes ServiceAccount the traces collector assumes via IRSA. Must differ from any other collector in the same namespace. | `string` | `"adot-traces-collector"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_collector_namespace"></a> [collector\_namespace](#output\_collector\_namespace) | Kubernetes namespace the traces collector is deployed into. |
| <a name="output_otlp_grpc_endpoint"></a> [otlp\_grpc\_endpoint](#output\_otlp\_grpc\_endpoint) | In-cluster OTLP gRPC endpoint applications send spans to (OTEL\_EXPORTER\_OTLP\_ENDPOINT). |
| <a name="output_otlp_http_endpoint"></a> [otlp\_http\_endpoint](#output\_otlp\_http\_endpoint) | In-cluster OTLP HTTP endpoint applications send spans to. POST OTLP to <endpoint>/v1/traces. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IRSA role assumed by the traces collector service account. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the IRSA role assumed by the traces collector service account. |
<!-- END_TF_DOCS -->
