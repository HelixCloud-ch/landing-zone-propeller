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

## IAM requirement (NOT managed here)

The **Fargate pod execution role** must have permission to write to CloudWatch
Logs. Attach the following actions to the pod execution role (owned by the
cluster project, not this module):

```json
{
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogStream",
    "logs:CreateLogGroup",
    "logs:DescribeLogStreams",
    "logs:PutLogEvents"
  ],
  "Resource": "*"
}
```

## ConfigMap limitations

- Changes to the ConfigMap only apply to **new pods**. Existing pods must be
  restarted to pick up changes.
- The ConfigMap cannot exceed 5300 characters.
- `Service` and `Input` sections are managed by Fargate and must not be set.
- Supported output plugins: `cloudwatch`, `cloudwatch_logs`, `es`,
  `firehose`, `kinesis_firehose`, `kinesis`.

## What does NOT belong here

- IAM policies or roles — these attach to the pod execution role in the cluster
  project.
- Fargate profiles — managed by the cluster project.
- Node-level or DaemonSet-based log collection — not applicable on Fargate.

## References

- [Start AWS Fargate logging](https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html)
- [AWS for Fluent Bit](https://github.com/aws/aws-for-fluent-bit)

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
