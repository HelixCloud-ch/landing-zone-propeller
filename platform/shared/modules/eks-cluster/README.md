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
- Remove Fargate entirely by destroying only the `eks-fargate` module while the
  cluster stays running.

## What it deploys

- **`aws_eks_cluster`** — configurable endpoint access, authentication mode
  (default: `API`), and control-plane log types (default: all five per AWS
  best practice).
- **Cluster IAM role** — trusts `eks.amazonaws.com`; attaches
  `AmazonEKSClusterPolicy` (resolved via data source, not a hardcoded ARN).
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
<!-- END_TF_DOCS -->
