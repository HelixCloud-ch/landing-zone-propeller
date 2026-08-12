# eks-addons

EKS managed add-ons for an Amazon EKS cluster. Manages CoreDNS and simple
config-light add-ons (vpc-cni, kube-proxy, pod-identity-agent, etc.) as EKS
managed add-on resources (`aws_eks_addon`). This project uses only the AWS
provider — no Helm or Kubernetes API access is required.

Add-ons with complex requirements (IRSA roles, Helm charts, multi-resource
orchestration) live in their own dedicated projects: `eks-lb-controller`,
`eks-observability`, `eks-autoscaler`.

## What it deploys

| Add-on | Mechanism | Toggle |
|--------|-----------|--------|
| CoreDNS | Dedicated module (`eks-addon-coredns`) | `install_coredns` (default true) |
| Base add-ons (vpc-cni, kube-proxy, pod-identity-agent, …) | Generic module (`eks-addon-base`) via `for_each` | `base_addons` map |

## Base add-ons (`base_addons`)

The `base_addons` variable is a map intended **exclusively for add-ons that
require little or no configuration** — typically just a version pin and at most
a simple `configuration_values` JSON string. Each key is an official EKS add-on
name; each value controls whether it is deployed, its pinned version, and an
optional configuration blob.

```hcl
base_addons = {
  vpc-cni    = { enabled = true, version = "v1.19.5-eksbuild.1" }
  kube-proxy = { enabled = true, version = "v1.32.0-eksbuild.2" }
  eks-pod-identity-agent = { enabled = false }
}
```

Add-ons with complex requirements — dedicated IRSA roles, Helm charts, non-
trivial orchestration, or compute-type awareness — get their own dedicated
project instead. Do **not** put those in `base_addons`.

New simple add-ons (e.g. `aws-ebs-csi-driver`, `snapshot-controller`) can be
added by the consumer in tfvars without any change to this project's code.

## CoreDNS

Managed here only when `install_coredns = true`. It is **required on
pure-Fargate clusters** — the default self-managed CoreDNS deployment cannot
schedule without nodes, so the managed add-on (with `coredns_compute_type =
"Fargate"`) is what provides in-cluster DNS. On **EC2 node-group clusters** EKS
already ships a working CoreDNS, so managing the add-on is optional; enable it
only to pin or upgrade the version deliberately.

## Compute type

`coredns_compute_type` controls where CoreDNS pods schedule. Set it to
`Fargate` on pure-Fargate clusters — this requires a `kube-system` Fargate
profile on the cluster (scoped to `k8s-app=kube-dns`), provisioned by the
`eks-cluster` project. Leave it null on EC2-based clusters to use the EKS
default.

On a pure-Fargate cluster, after the first apply you may need to roll CoreDNS so
it reschedules onto Fargate:

```bash
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status  deployment/coredns -n kube-system
```

## Pipeline inputs

`cluster_name` is injected from the `eks-cluster` step output. Do **not** set
it in `config.auto.tfvars`.

```yaml
- name: eks-addons
  target: workload-account
  inputs:
    - name: eks-cluster.cluster_name
      var: cluster_name
```

## What does NOT belong here

- Cluster infrastructure (control plane, Fargate profiles, node groups) — that
  lives in the `eks-cluster` project.
- AWS Load Balancer Controller — that lives in `eks-lb-controller`.
- CloudWatch Observability, Cluster Autoscaler — those get their own projects.
- Cross-account ECR pull policy — that lives in the ECR-pull project.
- IAM policies or roles for unrelated services.

## References

- [EKS CoreDNS management](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html)
- [EKS managed add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [EKS upgrade runbook](../../../../notes/wiki/operations/eks-upgrade-runbook.md)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_base_addon"></a> [base\_addon](#module\_base\_addon) | ../../../shared/modules/eks-addon-base | n/a |
| <a name="module_coredns"></a> [coredns](#module\_coredns) | ../../../shared/modules/eks-addon-coredns | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_base_addons"></a> [base\_addons](#input\_base\_addons) | Map of EKS managed add-ons to install via the generic eks-addon-base module. Intended for add-ons that need only a version pin and at most a simple configuration\_values JSON string. Keys must match official EKS add-on names. Add-ons requiring dedicated IRSA roles, Helm charts, or complex orchestration should use their own dedicated project instead. | <pre>map(object({<br/>    enabled              = optional(bool, false)<br/>    version              = optional(string, null)<br/>    configuration_values = optional(string, null)<br/>  }))</pre> | <pre>{<br/>  "eks-pod-identity-agent": {<br/>    "enabled": false<br/>  },<br/>  "kube-proxy": {<br/>    "enabled": false<br/>  },<br/>  "vpc-cni": {<br/>    "enabled": false<br/>  }<br/>}</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Sourced from the eks-cluster project output. | `string` | n/a | yes |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_coredns_compute_type"></a> [coredns\_compute\_type](#input\_coredns\_compute\_type) | Compute type CoreDNS pods are scheduled on. Set to "Fargate" for pure-Fargate clusters (requires a kube-system Fargate profile on the cluster). Leave null for EC2-based clusters to use the EKS default. | `string` | `null` | no |
| <a name="input_coredns_version"></a> [coredns\_version](#input\_coredns\_version) | Pinned version of the CoreDNS managed EKS add-on (e.g. "v1.11.4-eksbuild.40"). Bump in lockstep with the cluster Kubernetes version per the EKS upgrade runbook. Null lets EKS pick the default for the cluster's Kubernetes release. Ignored when install\_coredns is false. | `string` | `null` | no |
| <a name="input_install_coredns"></a> [install\_coredns](#input\_install\_coredns) | Whether to manage the CoreDNS EKS add-on here. Must be true on pure-Fargate clusters (the default self-managed CoreDNS cannot schedule without nodes). On EC2 node-group clusters EKS provides a working CoreDNS by default, so enable this only to pin or upgrade the add-on version deliberately. | `bool` | `true` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the EKS cluster is deployed. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_base_addon_versions"></a> [base\_addon\_versions](#output\_base\_addon\_versions) | Map of installed base add-on names to their resolved versions. Only includes enabled add-ons. |
| <a name="output_coredns_addon_arn"></a> [coredns\_addon\_arn](#output\_coredns\_addon\_arn) | ARN of the CoreDNS managed add-on. Null when install\_coredns = false. |
| <a name="output_coredns_addon_version"></a> [coredns\_addon\_version](#output\_coredns\_addon\_version) | Resolved version of the installed CoreDNS managed add-on. Null when install\_coredns = false. |
<!-- END_TF_DOCS -->