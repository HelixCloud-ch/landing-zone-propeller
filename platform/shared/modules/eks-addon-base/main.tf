# Generic EKS managed add-on — one addon per invocation.
#
# For addons that only need a version pin and resolve-conflicts semantics,
# without custom configuration_values. Examples: vpc-cni, kube-proxy,
# eks-pod-identity-agent, aws-ebs-csi-driver.
#
# Addons with non-trivial configuration (CoreDNS computeType, CloudWatch
# Observability, LB Controller Helm) have their own dedicated modules.
#
# Version resolution: when addon_version is null, the most recent compatible
# version for the cluster's Kubernetes release is resolved automatically via
# data.aws_eks_addon_version.

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_addon_version" "this" {
  addon_name         = var.addon_name
  kubernetes_version = data.aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "this" {
  cluster_name                = var.cluster_name
  addon_name                  = var.addon_name
  addon_version               = coalesce(var.addon_version, data.aws_eks_addon_version.this.version)
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  configuration_values        = var.configuration_values
  service_account_role_arn    = var.service_account_role_arn
  preserve                    = var.preserve
  tags                        = var.tags
}
