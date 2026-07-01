# eks-cluster

Provisions a compute-agnostic Amazon EKS cluster: control plane, cluster IAM
role, and optionally an OIDC provider for IRSA. Deliberately contains no
compute resources — node groups, Fargate profiles, and their IAM roles live in
separate modules.

## Why separate from compute

The cluster control plane and its OIDC provider can outlive multiple compute
transitions. Adding or replacing EC2 managed node groups or Fargate profiles
does not require destroying and recreating the cluster. Keeping the cluster
module compute-free means you can:

- Start with Fargate-only and add EC2 node groups later without touching this
  module.
- Move from pure Fargate to a mixed EC2+Fargate mode by creating an EC2 node
  group alongside existing Fargate profiles.
- Remove Fargate entirely by destroying only the `eks-fargate-profiles` module
  while the cluster stays running.

## What it deploys

- **`aws_eks_cluster`** — configurable endpoint access, authentication mode
  (default: `API`), and control-plane log types (default: all five per AWS
  best practice).
- **Cluster IAM role** — trusts `eks.amazonaws.com`; attaches
  `AmazonEKSClusterPolicy` (resolved via data source, not a hardcoded ARN).
  Set `create_cluster_role = false` and pass `cluster_role_arn` to consume an
  externally-managed role instead (the enabler for centralized role
  management); the external role must trust `eks.amazonaws.com` and carry
  `AmazonEKSClusterPolicy`.
- **OIDC provider** (optional, default: enabled) — registers the cluster OIDC
  issuer in IAM for IAM Roles for Service Accounts (IRSA).

## OIDC provider and Pod Identity

This module manages the OIDC **identity provider** registration in IAM
(`aws_iam_openid_connect_provider`), gated on `enable_oidc_provider`.

The OIDC **issuer** URL is a different thing: EKS creates it automatically on
every cluster as part of `CreateCluster` — it is always present on
`aws_eks_cluster.this.identity[0].oidc[0].issuer`, regardless of whether this
module creates the IAM-side provider registration.

| Compute type | IAM method | `enable_oidc_provider` |
|--------------|-----------|------------------------|
| **Fargate** | IRSA (OIDC) only | `true` — required |
| EC2 (Pod Identity only) | Pod Identity Agent | `false` |
| EC2 (IRSA only) | IRSA (OIDC) | `true` |
| Mixed EC2 + Fargate | Both coexist | `true` |

**Why Fargate requires OIDC/IRSA:** The Pod Identity Agent runs as a DaemonSet
on EC2 nodes. DaemonSets do not run on Fargate, so the agent can never start
there. IRSA/OIDC is the only supported IAM credential mechanism for Fargate
pods (AWS docs: *"Pods that run on AWS Fargate aren't supported"* for Pod
Identity — [source](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)).

**Pod Identity Agent is not managed here.** It is an EKS managed add-on
(like CoreDNS) and belongs in the add-ons layer alongside `coredns` and the
AWS Load Balancer Controller, not in the cluster module. Add it to
`eks-addons-1` with `addon_name = "eks-pod-identity-agent"` when the cluster
has EC2 nodes that need Pod Identity.

## Endpoint access

`endpoint_private_access` (default `true`) and `endpoint_public_access`
(default `false`) are exposed as variables. AWS recommends keeping the private
endpoint enabled whenever the public endpoint is restricted or disabled, so
that kubelets (EC2 or Fargate) can reach the control plane from within the VPC.

## What does NOT belong here

- No Fargate profiles or pod execution role — see the `eks-fargate` module.
- No EC2 managed node groups — future `eks-node-group` module.
- No add-ons (CoreDNS, kube-proxy, LB Controller) — separate project.
- No application workloads.

## References

- [aws_eks_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster)
- [Amazon EKS control plane logging](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html)
- [EKS Pod Identity — limitations (Fargate not supported)](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Create an IAM OIDC provider for your cluster](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.52.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_iam_openid_connect_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy) | data source |
| [aws_iam_policy_document.cluster_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [tls_certificate.oidc](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_authentication_mode"></a> [authentication\_mode](#input\_authentication\_mode) | EKS access-config authentication mode. 'API' (recommended for new clusters — no ConfigMap dependency), 'CONFIG\_MAP', or 'API\_AND\_CONFIG\_MAP' (migration path from ConfigMap-based clusters). | `string` | `"API"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. | `string` | n/a | yes |
| <a name="input_cluster_role_arn"></a> [cluster\_role\_arn](#input\_cluster\_role\_arn) | ARN of an externally-managed cluster IAM role. Required when create\_cluster\_role is false; ignored otherwise. The role must trust eks.amazonaws.com and carry AmazonEKSClusterPolicy. | `string` | `null` | no |
| <a name="input_create_cluster_role"></a> [create\_cluster\_role](#input\_create\_cluster\_role) | Create the cluster IAM role. Set false to supply an externally-managed role via cluster\_role\_arn (e.g. centralized role management). | `bool` | `true` | no |
| <a name="input_eks_version"></a> [eks\_version](#input\_eks\_version) | Pinned Kubernetes minor version for the cluster (e.g. "1.30"). Must be updated explicitly; no automatic upgrades. | `string` | n/a | yes |
| <a name="input_enable_oidc_provider"></a> [enable\_oidc\_provider](#input\_enable\_oidc\_provider) | Create an IAM OIDC identity provider for this cluster, which enables IAM<br/>Roles for Service Accounts (IRSA).<br/><br/>**Required when using Fargate.** The EKS Pod Identity Agent runs as a<br/>DaemonSet on EC2 nodes and is therefore incompatible with Fargate<br/>(AWS docs: "Pods that run on AWS Fargate aren't supported"). IRSA/OIDC is<br/>the only supported mechanism for granting AWS IAM permissions to pods<br/>running on Fargate.<br/><br/>For EC2-only clusters, IRSA and EKS Pod Identity can coexist on the same<br/>cluster: set this to true if any workload uses IRSA, leave it false if all<br/>workloads use Pod Identity exclusively. | `bool` | `true` | no |
| <a name="input_enabled_cluster_log_types"></a> [enabled\_cluster\_log\_types](#input\_enabled\_cluster\_log\_types) | Control-plane log types forwarded to CloudWatch. Defaults to all five types per AWS best practice. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_endpoint_private_access"></a> [endpoint\_private\_access](#input\_endpoint\_private\_access) | Enable private API server endpoint (reachable from within the VPC). Should be true whenever public access is disabled or restricted, so that Fargate/node kubelets can reach the control plane. | `bool` | `true` | no |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Enable public API server endpoint. Set to false for private-only clusters (recommended for production); set to true when operators need to reach the API without a VPN or Direct Connect. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the symmetric CMK used to encrypt Kubernetes secrets. Required when secrets\_encryption\_enabled is true; ignored otherwise. | `string` | `null` | no |
| <a name="input_secrets_encryption_enabled"></a> [secrets\_encryption\_enabled](#input\_secrets\_encryption\_enabled) | When true, enables CMK envelope encryption for Kubernetes secrets using kms\_key\_arn. | `bool` | `false` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | App-tier private subnet IDs (one per availability zone) used for Fargate profiles and cluster cross-account ENIs. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the workload VPC. Sourced from workload-vpc.vpc\_id. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64-encoded certificate authority data for the cluster API server TLS certificate. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | Private API server endpoint URL. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | ID of the EKS-managed cluster security group. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the IAM OIDC identity provider. Null when enable\_oidc\_provider is false. |
| <a name="output_oidc_provider_url"></a> [oidc\_provider\_url](#output\_oidc\_provider\_url) | Issuer URL of the OIDC provider without the https:// prefix. Null when enable\_oidc\_provider is false. |
<!-- END_TF_DOCS -->
