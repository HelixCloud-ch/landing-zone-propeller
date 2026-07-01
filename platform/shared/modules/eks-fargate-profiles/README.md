# eks-fargate-profiles

Creates the Fargate pod execution role and Fargate profiles for an existing EKS
cluster. Designed to be used alongside the `eks-cluster` module, not as a
replacement for it.

## Why separate from the cluster

The pod execution role and Fargate profiles are compute-specific. Keeping them
in a dedicated module means:

- You can migrate a cluster from pure Fargate to a mixed EC2+Fargate mode (or
  pure EC2) without destroying and recreating the cluster.
- You can add Fargate profiles to an existing EC2-based cluster without touching
  cluster resources.
- The `eks-cluster` module stays generic and reusable regardless of the chosen
  compute model.

## What it deploys

- **Pod execution roles** — trusted by `eks-fargate-pods.amazonaws.com`; each
  carries the `AmazonEKSFargatePodExecutionRolePolicy` managed policy for ECR
  image pull and CloudWatch log delivery. The trust policy includes the
  confused-deputy `aws:SourceArn` guard scoped to this cluster's Fargate
  profiles. A `default` role always exists; define more under
  `pod_execution_roles` and reference them per profile.
- **Fargate profiles** (`var.fargate_profiles`) — one per entry; each selects
  pods by namespace and optional labels, lands in its own `subnet_ids`, and
  assumes the role named by `pod_execution_role` (or `default`).

## Pod execution roles

The pod execution role is the Fargate **runtime** identity — it pulls images
and ships logs. It is not the pod's workload identity (that is IRSA). One role
serves many profiles by default. Give profiles a dedicated role only when you
need to isolate what the runtime can pull — most commonly cross-account ECR,
where each ECR's repository policy grants a specific role ARN.

Roles are keyed. Every profile that omits `pod_execution_role` (or sets it to
`"default"`) shares the always-present `default` role. Define extra roles and
point profiles at them by key; profiles sharing a role use the same key:

```hcl
pod_execution_roles = {
  test = {}
  prod = {}
}

fargate_profiles = [
  { name = "test", namespace = "test", subnet_ids = ["subnet-a"], pod_execution_role = "test" },
  { name = "prod", namespace = "prod", subnet_ids = ["subnet-b"], pod_execution_role = "prod" },
  { name = "shared", namespace = "shared", subnet_ids = ["subnet-a"] }, # uses "default"
]
```

Cross-account ECR pull policies are attached to a specific role by name via the
`eks-ecr-pull` project (run once per role/registry pair) — not set here. The
`additional_policy_arns` field exists for direct module users who prefer to
attach scoping inline.

### Bring your own role

Set `arn` on a role entry to consume an externally-managed role instead of
creating one — the enabler for centralized role management. When `arn` is set,
the module creates nothing for that key and `additional_policy_arns` must be
empty (the external owner manages the role's policies; a non-empty list is a
validation error). The implicit `default` role can also be externalized by
supplying a `default` key with an `arn`.

```hcl
pod_execution_roles = {
  default = { arn = "arn:aws:iam::111122223333:role/central-fargate-pod-exec" }
  test    = {}  # still module-created
}
```

## On `kube-system` and CoreDNS

The default for `fargate_profiles` is `[]` — intentionally empty. You only
need a `kube-system` profile when the cluster has **no EC2 nodes**, because
CoreDNS is deployed to `kube-system` and must have somewhere to run. If your
cluster has EC2 managed node groups, CoreDNS runs on those and no
`kube-system` Fargate profile is needed. Add it only when required:

```hcl
fargate_profiles = [
  { name = "app", namespace = "my-app", subnet_ids = ["subnet-a", "subnet-b"] },
  # Add the entry below only for pure-Fargate clusters (no EC2 nodes):
  { name = "coredns", namespace = "kube-system", labels = { "k8s-app" = "kube-dns" }, subnet_ids = ["subnet-a", "subnet-b"] },
]
```

Note the label selector on the CoreDNS entry — it narrows the profile to
CoreDNS pods only, so other `kube-system` pods are not accidentally scheduled
on Fargate.

## Per-profile subnets

Each profile carries its own `subnet_ids` (there is no module-level default),
so different profiles can land in different subnets — useful when a team owns a
dedicated subnet, or to spread profiles across tiers. Subnets must be private,
in the cluster VPC, with a route to the cluster API endpoint.

```hcl
fargate_profiles = [
  { name = "app", namespace = "my-app", subnet_ids = ["subnet-shared-a", "subnet-shared-b"] },
  { name = "team-x", namespace = "team-x", subnet_ids = ["subnet-teamx-a", "subnet-teamx-b"] },
]
```

When consumed through the `eks-cluster` project, you express this as a
per-profile `subnet_tier` (resolved to subnet IDs from the VPC output) rather
than raw IDs.

## What does NOT belong here

- No `aws_eks_cluster` — use the `eks-cluster` module.
- No EC2 managed node groups — future `eks-node-group` module.
- No add-ons (CoreDNS, LB Controller) — separate project.

## References

- [aws_eks_fargate_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_fargate_profile)
- [Amazon EKS Pod execution IAM role](https://docs.aws.amazon.com/eks/latest/userguide/pod-execution-role.html)
- [Manage CoreDNS for DNS in Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.52.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_fargate_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_fargate_profile) | resource |
| [aws_iam_role.pod_exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.pod_exec_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.pod_exec_base](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy.pod_exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy) | data source |
| [aws_iam_policy_document.pod_exec_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Sourced from the eks-cluster module output. | `string` | n/a | yes |
| <a name="input_fargate_profiles"></a> [fargate\_profiles](#input\_fargate\_profiles) | Fargate profiles to create. Each entry produces one aws\_eks\_fargate\_profile with a single selector and its own subnet\_ids (private subnets with a route to the cluster API endpoint). pod\_execution\_role selects which role (a key in pod\_execution\_roles, or the implicit 'default') the profile assumes; profiles sharing a role reference the same key. Different profiles may target different subnets — e.g. a team with a dedicated subnet. Use multiple entries with the same namespace but different labels for more granular pod scheduling. Default is empty — callers opt in to the namespaces they need. | <pre>list(object({<br/>    name               = string<br/>    namespace          = string<br/>    labels             = optional(map(string), {})<br/>    subnet_ids         = list(string)<br/>    pod_execution_role = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_pod_execution_role_name"></a> [pod\_execution\_role\_name](#input\_pod\_execution\_role\_name) | Name of the default Fargate pod execution IAM role (the 'default' key). Defaults to '<cluster\_name>-fargate-pod-exec'. Named roles from pod\_execution\_roles are named '<cluster\_name>-fargate-pod-exec-<key>'. | `string` | `null` | no |
| <a name="input_pod_execution_roles"></a> [pod\_execution\_roles](#input\_pod\_execution\_roles) | Named Fargate pod execution roles beyond the always-present 'default'. For each key: leave arn null to have this module create the role (base AmazonEKSFargatePodExecutionRolePolicy plus any additional\_policy\_arns), or set arn to consume an externally-managed role (e.g. centralized role management) — in which case the module creates nothing for that key. The 'default' key may be supplied here to externalize the default role too. Profiles reference a role by key via pod\_execution\_role; multiple profiles may share the same key. | <pre>map(object({<br/>    arn                    = optional(string)<br/>    additional_policy_arns = optional(list(string), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_fargate_profile_names"></a> [fargate\_profile\_names](#output\_fargate\_profile\_names) | Names of all Fargate profiles created by this module. |
| <a name="output_pod_execution_role_arn"></a> [pod\_execution\_role\_arn](#output\_pod\_execution\_role\_arn) | Effective ARN of the default Fargate pod execution role. Convenience accessor for pod\_execution\_role\_arns["default"]. |
| <a name="output_pod_execution_role_arns"></a> [pod\_execution\_role\_arns](#output\_pod\_execution\_role\_arns) | Map of role key to effective IAM role ARN (module-created or externally supplied), including 'default'. |
| <a name="output_pod_execution_role_name"></a> [pod\_execution\_role\_name](#output\_pod\_execution\_role\_name) | Name of the default Fargate pod execution role when this module manages it; null when the default role is externally supplied. |
| <a name="output_pod_execution_role_names"></a> [pod\_execution\_role\_names](#output\_pod\_execution\_role\_names) | Map of role key to IAM role name, for module-managed roles only. External roles are excluded — their names are owned elsewhere. |
<!-- END_TF_DOCS -->
