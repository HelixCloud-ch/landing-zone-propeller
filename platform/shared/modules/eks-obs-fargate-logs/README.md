# eks-obs-fargate-logs

Native EKS Fargate log router — deploys the `aws-observability` namespace and
the `aws-logging` ConfigMap that activates the built-in Fluent Bit process
running inside every Fargate micro-VM.

## What it does

On EKS Fargate, AWS runs a Fluent Bit instance inside each pod's micro-VM. You
do not deploy a Fluent Bit pod; you configure the router via a ConfigMap. This
module creates:

1. A `aws-observability` Kubernetes namespace (required label `aws-observability: enabled`)
2. A `aws-logging` ConfigMap in that namespace with Filter, Output, and Parser sections

Container stdout/stderr is routed to **CloudWatch Logs** (`destination = "cloudwatch"`).
The Kubernetes filter enriches each log record with pod/namespace/container metadata.

## IAM (managed here)

The Fargate native log router writes to CloudWatch under the **Fargate pod
execution role** — not an IRSA role — because the built-in Fluent Bit runs on
Fargate infrastructure, not as a pod you control. When `pod_execution_role_name`
is supplied, this module attaches an inline policy granting the router the
CloudWatch Logs permissions it needs (`CreateLogGroup`, `CreateLogStream`,
`DescribeLogStreams`, `PutLogEvents`, `PutRetentionPolicy`), scoped to the
configured log group. Without this the log group is never created and no logs
ship.

If several Fargate profiles use distinct pod execution roles and all must ship
logs, attach the policy to each — pass the shared/default role here and extend
for the others, or invoke the module per role.

## ConfigMap limitations

- Changes to the ConfigMap only apply to **new pods**. Existing pods must be
  restarted to pick up changes.
- The ConfigMap cannot exceed 5300 characters.
- `Service` and `Input` sections are managed by Fargate and must not be set.
- Supported output plugins: `cloudwatch`, `cloudwatch_logs`, `es`,
  `firehose`, `kinesis_firehose`, `kinesis`.

## What does NOT belong here

- Fargate profiles and the pod execution role itself — managed by the cluster
  project. This module only attaches a logging policy to the role it is given.
- Node-level or DaemonSet-based log collection — not applicable on Fargate.

## References

- [Start AWS Fargate logging](https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html)
- [AWS for Fluent Bit](https://github.com/aws/aws-for-fluent-bit)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role_policy.fargate_logging](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [kubernetes_config_map_v1.aws_logging](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_namespace_v1.aws_observability](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_destination"></a> [destination](#input\_destination) | Log destination type. 'cloudwatch' sends container logs to CloudWatch Logs via the cloudwatch\_logs Fluent Bit output plugin. Additional destinations ('firehose', 'opensearch') can be added in a later iteration. | `string` | `"cloudwatch"` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | CloudWatch Logs log group name to route container logs into. The log group is created automatically by the cloudwatch\_logs plugin (auto\_create\_group = true). Convention: '/aws/eks/<cluster\_name>/application'. | `string` | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch Logs retention in days for the log group. 0 means never expire. Fargate creates the group on first log delivery; retention is enforced by the plugin. | `number` | `30` | no |
| <a name="input_log_stream_prefix"></a> [log\_stream\_prefix](#input\_log\_stream\_prefix) | Prefix for each CloudWatch Logs log stream. Each stream is named '<prefix><pod-name>'. Convention: 'from-fargate-'. | `string` | `"from-fargate-"` | no |
| <a name="input_pod_execution_role_name"></a> [pod\_execution\_role\_name](#input\_pod\_execution\_role\_name) | Name of the Fargate pod execution role that the native log router runs under. When set, this module attaches an inline policy granting the CloudWatch Logs permissions the router needs to create and write the log group. Required for the CloudWatch destination to work — the built-in Fluent Bit uses the pod execution role, not an IRSA role. Leave null only when the role already carries equivalent logging permissions. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster and the log destination. Required when destination = 'cloudwatch'. | `string` | n/a | yes |
| <a name="input_ship_fluentbit_process_logs"></a> [ship\_fluentbit\_process\_logs](#input\_ship\_fluentbit\_process\_logs) | Whether to ship Fluent Bit process (internal) logs to CloudWatch. Adds extra log ingestion and storage cost. Useful for debugging log routing issues; disable for steady-state environments. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | CloudWatch Logs log group name configured in the Fargate log router. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Name of the aws-observability namespace created by this module. |
<!-- END_TF_DOCS -->
