# eks-obs-tracing

Transaction Search tracing backend for EKS workloads (and any other workloads
in the account that emit traces via X-Ray / OTel → X-Ray).

## What it does

Configures three account/region-scoped AWS resources to enable CloudWatch
Transaction Search:

1. **`aws_xray_trace_segment_destination`** — routes all X-Ray
   `PutTraceSegments` calls to CloudWatch Logs (the `aws/spans` log group)
   instead of the legacy X-Ray trace store.
2. **`aws_xray_indexing_rule` ("Default")** — sets the percentage of trace IDs
   that are indexed as trace summaries for end-to-end search and analytics.
   1% is free; 100% stores all spans but increases cost.
3. **`aws_cloudwatch_log_resource_policy`** — resource-based policy granting
   `xray.amazonaws.com` permission to write to `aws/spans` and
   `/aws/application-signals/data`. Required for API-based enablement (the
   console configures this automatically).

## Scope warning — account/region level

This module is **not per-cluster**. Enabling Transaction Search affects the
entire AWS account in the configured region. Every workload that sends spans to
X-Ray — regardless of cluster — will have traces routed to CloudWatch Logs.
Deciding where to manage this (platform project, landing-zone project,
observability account).

## App team responsibility

This module only enables the backend. Application teams must:
- Instrument their code with the OpenTelemetry SDK (not the X-Ray SDK/Daemon,
  which is in maintenance mode since 2026-02-25)
- Point the OTel SDK at an ADOT Collector endpoint
- The collector exports spans to the X-Ray OTLP endpoint → they land in `aws/spans`

## Terraform lifecycle note

`aws_xray_trace_segment_destination` and `aws_xray_indexing_rule` are idempotent
PUT operations in AWS. Removing them from Terraform state does **not** revert the
AWS configuration; they must be actively reset via the console or CLI.

## What does NOT belong here

- Cluster-level IAM (IRSA roles, collector service accounts) — those live in
  `eks-obs-fargate-metrics` or the app's own infra.
- ADOT Collector deployment — `eks-obs-fargate-metrics` for Fargate.
- OTel SDK instrumentation — app team responsibility.

## References

- [CloudWatch Transaction Search](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Transaction-Search.html)
- [Enable Transaction Search](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Enable-TransactionSearch.html)
- [X-Ray SDKs/Daemon → OTel migration](https://aws.amazon.com/blogs/mt/aws-x-ray-sdks-daemon-migration-to-opentelemetry/)

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
