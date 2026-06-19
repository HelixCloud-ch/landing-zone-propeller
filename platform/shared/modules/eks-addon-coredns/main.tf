# CoreDNS managed EKS add-on.
#
# EKS installs CoreDNS as a self-managed add-on on every cluster, annotated
# eks.amazonaws.com/compute-type=ec2. On a pure-Fargate cluster those pods stay
# Pending. Converting CoreDNS to a managed add-on with computeType=Fargate
# reschedules it onto Fargate (a kube-system Fargate profile must also exist).
# The computeType key is part of the documented coredns add-on configuration
# schema (aws eks describe-addon-configuration --addon-name coredns).

locals {
  configuration_values = var.compute_type != null ? { computeType = var.compute_type } : {}
}

resource "aws_eks_addon" "this" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  configuration_values = length(local.configuration_values) > 0 ? jsonencode(local.configuration_values) : null
}
