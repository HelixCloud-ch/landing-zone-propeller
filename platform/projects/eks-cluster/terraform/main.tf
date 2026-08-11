module "cluster" {
  source = "../../../shared/modules/eks-cluster"

  cluster_name = var.cluster_name
  eks_version  = var.eks_version

  vpc_id     = var.vpc_id
  subnet_ids = local.cluster_subnets

  authentication_mode       = var.authentication_mode
  enabled_cluster_log_types = var.enabled_cluster_log_types

  secrets_encryption_enabled = var.secrets_encryption_enabled
  kms_key_arn                = var.kms_key_arn

  additional_security_group_ids = local.cluster_additional_security_group_ids
}

# ── Fargate profiles (opt-in via fargate_profiles) ────────────────────────────

module "fargate_profiles" {
  count  = local.create_fargate ? 1 : 0
  source = "../../../shared/modules/eks-fargate-profiles"

  cluster_name = module.cluster.cluster_name

  pod_execution_roles = local.pod_execution_roles
  fargate_profiles    = local.fargate_profiles_resolved
}

# ── EC2 managed node groups (opt-in via node_groups) ──────────────────────────

module "node_groups" {
  for_each = local.node_groups_resolved
  source   = "../../../shared/modules/eks-nodegroup"

  cluster_name    = module.cluster.cluster_name
  node_group_name = each.value.name
  subnet_ids      = each.value.subnet_ids

  instance_types  = each.value.instance_types
  capacity_type   = each.value.capacity_type
  ami_type        = each.value.ami_type
  release_version = each.value.release_version
  disk_size       = each.value.disk_size

  desired_size    = each.value.desired_size
  min_size        = each.value.min_size
  max_size        = each.value.max_size
  max_unavailable = each.value.max_unavailable

  labels = each.value.labels
  taints = each.value.taints
}

# ── Additional cluster admin access entries ───────────────────────────────────

data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "additional_admins" {
  for_each = local.additional_admin_arns

  cluster_name  = module.cluster.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "additional_admins" {
  for_each = local.additional_admin_arns

  cluster_name  = module.cluster.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.additional_admins]
}
