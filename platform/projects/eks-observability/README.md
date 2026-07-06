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
<!-- END_TF_DOCS -->
