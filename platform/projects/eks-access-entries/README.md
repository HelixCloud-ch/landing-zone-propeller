# eks-access-entries

Registers IAM principals as EKS access entries and associates cluster-access policies, giving users visibility into the cluster through the AWS Console and kubectl.

Supports two input paths:

- **SSO-discovered** (`sso_access_entries`): discovers `AWSReservedSSO_*` roles created by IAM Identity Center dynamically at plan time — no ARN hardcoding needed.
- **Direct ARN** (`direct_access_entries`): registers any IAM role or user whose ARN is already known (CI/CD roles, break-glass IAM users, cross-account roles).

## Why this project exists

The EKS console Overview and Resources tabs require two permission layers:

1. **IAM layer** — `eks:AccessKubernetesApi` and related EKS describe actions, covered by `AmazonEKSDashboardConsoleReadOnly` attached to the permission sets in `base-sso`.
2. **Kubernetes RBAC layer** — a ClusterRole binding inside the cluster, provided here via the EKS access entry API.

Both layers must be present. This project handles layer 2.

## SSO role discovery

When IAM Identity Center assigns a permission set to an account, it creates a role named `AWSReservedSSO_<PermissionSetName>_<random-16-char-suffix>` under `/aws-reserved/sso.amazonaws.com/<sso_region>/`. The suffix is not predictable — it changes if the assignment is ever deleted and recreated.

The project discovers the role ARN at plan time using the `aws_iam_roles` data source filtered by `name_regex` and `path_prefix`. If a permission set has not been assigned to the account yet, the role is not found and the entry is silently skipped (no error, no drift). The next apply after the assignment is created will pick it up automatically.

## Default mapping

The default `sso_access_entries` value maps the three base-sso permission sets:

| Key | Permission set (default name) | EKS cluster-access policy | Kubernetes equivalent |
|---|---|---|---|
| `readonly` | `ReadOnly` | `AmazonEKSViewPolicy` | `view` — read all resources cluster-wide |
| `poweruser` | `PowerUser` | `AmazonEKSEditPolicy` | `edit` — create and update resources, no RBAC/quota writes |
| `admin` | `Admin` | `AmazonEKSClusterAdminPolicy` | `cluster-admin` — full cluster access |

Override `sso_access_entries` entirely to rename keys, use different permission set names, change policies, or add entries for extra permission sets.

## Operational notes

**Re-assignment suffix change.** If a permission set is deleted and reassigned to the account, IAM Identity Center creates a new role with a different suffix. The next `terraform apply` discovers the new ARN and replaces the access entry automatically (destroy old + create new). No manual intervention needed.

**Key namespacing.** SSO entries are stored internally with a `sso_` prefix; direct entries with `direct_`. This prevents key collisions if you use the same string as a key in both maps.

**Deploy runner access.** IAM roles for VPC-attached deploy runners are registered in `eks-cluster` via `additional_admin_role_names`, not here. Use `direct_access_entries` only for principals not managed by the cluster project.

**No VPC runner required.** This project interacts only with the EKS and IAM control planes — not with the Kubernetes API. It does not need a VPC-attached deploy runner.

## Pipeline inputs

`cluster_name` is injected by the pipeline from the `eks-cluster` step outputs. Do not set it in `config.auto.tfvars`.

```yaml
- project: eks-access-entries
  source: eks-access-entries
  target: workload-account
  depends_on: [eks-cluster]
  inputs:
    - name: eks-cluster.cluster_name
      var: cluster_name
```

## What does NOT belong here

- `AmazonEKSDashboardConsoleReadOnly` policy attachment — managed in `base-sso`.
- Deploy runner / CI-CD role access entries — those belong in `eks-cluster` via `additional_admin_role_names`.
- Namespace-scoped access — use a custom project with `access_scope.type = "namespace"` if needed.

## References

- [Referencing permission sets in EKS cluster config maps](https://docs.aws.amazon.com/singlesignon/latest/userguide/referencingpermissionsets.html) — SSO role naming and ARN format
- [View Kubernetes resources in the AWS Management Console](https://docs.aws.amazon.com/eks/latest/userguide/view-kubernetes-resources.html) — required IAM + RBAC permissions
- [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html) — API documentation
- [Access policy permissions reference](https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html) — what each EKS access policy grants

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_access_entry.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_iam_roles.sso](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_roles) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Sourced from the eks-cluster project output. | `string` | n/a | yes |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_direct_access_entries"></a> [direct\_access\_entries](#input\_direct\_access\_entries) | Map of key → { principal\_arn, policy\_arn } for IAM principals whose ARN is known directly. | `map(object({ principal_arn = string, policy_arn = string }))` | `{}` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the EKS cluster is deployed. | `string` | n/a | yes |
| <a name="input_sso_access_entries"></a> [sso\_access\_entries](#input\_sso\_access\_entries) | Map of key → { permission\_set\_name, policy\_arn } for IAM Identity Center permission sets. | `map(object({ permission_set_name = string, policy_arn = string }))` | see default | no |
| <a name="input_sso_region"></a> [sso\_region](#input\_sso\_region) | AWS region where IAM Identity Center is homed. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_entry_arns"></a> [access\_entry\_arns](#output\_access\_entry\_arns) | Map of entry key to EKS access entry ARN. SSO entries prefixed with 'sso\_', direct with 'direct\_'. |
| <a name="output_principal_arns"></a> [principal\_arns](#output\_principal\_arns) | Map of entry key to the IAM principal ARN registered as an access entry. |
<!-- END_TF_DOCS -->
