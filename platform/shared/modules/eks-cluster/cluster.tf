# Additional security groups (created outside this module — e.g. by the
# eks-cluster project today, or a centralized security-group plane later) are
# attached to the cluster's cross-account ENIs so connected networks can reach
# the private API endpoint. This module only consumes the IDs; it owns no
# security group of its own.

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = local.cluster_role_arn
  version  = var.eks_version

  access_config {
    authentication_mode = var.authentication_mode
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    security_group_ids      = length(var.additional_security_group_ids) > 0 ? var.additional_security_group_ids : null
  }

  dynamic "encryption_config" {
    for_each = var.secrets_encryption_enabled ? [1] : []
    content {
      provider {
        key_arn = var.kms_key_arn
      }
      resources = ["secrets"]
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
  ]
}
