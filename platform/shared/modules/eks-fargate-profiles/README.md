# eks-fargate

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

- **Pod execution role** — trusted by `eks-fargate-pods.amazonaws.com`; carries
  the `AmazonEKSFargatePodExecutionRolePolicy` managed policy for ECR image
  pull and CloudWatch log delivery. The trust policy includes the confused-deputy
  `aws:SourceArn` guard scoped to this cluster's Fargate profiles.
- **Fargate profiles** (`var.fargate_profiles`) — one per entry; each selects
  pods by namespace and optional labels.

## On `kube-system` and CoreDNS

The default for `fargate_profiles` is `[]` — intentionally empty. You only
need a `kube-system` profile when the cluster has **no EC2 nodes**, because
CoreDNS is deployed to `kube-system` and must have somewhere to run. If your
cluster has EC2 managed node groups, CoreDNS runs on those and no
`kube-system` Fargate profile is needed. Add it only when required:

```hcl
fargate_profiles = [
  { name = "app", namespace = "my-app" },
  # Add the entry below only for pure-Fargate clusters (no EC2 nodes):
  { name = "coredns", namespace = "kube-system", labels = { "k8s-app" = "kube-dns" } },
]
```

Note the label selector on the CoreDNS entry — it narrows the profile to
CoreDNS pods only, so other `kube-system` pods are not accidentally scheduled
on Fargate.

## What does NOT belong here

- No `aws_eks_cluster` — use the `eks-cluster` module.
- No EC2 managed node groups — future `eks-node-group` module.
- No add-ons (CoreDNS, LB Controller) — separate project.

## References

- [aws_eks_fargate_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_fargate_profile)
- [Amazon EKS Pod execution IAM role](https://docs.aws.amazon.com/eks/latest/userguide/pod-execution-role.html)
- [Manage CoreDNS for DNS in Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html)

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
