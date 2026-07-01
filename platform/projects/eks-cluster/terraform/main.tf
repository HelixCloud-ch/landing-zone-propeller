locals {
  # aws_eks_cluster takes a single vpc_config block, so all selected cluster
  # tiers are flattened into one subnet_ids list for the control-plane ENIs.
  cluster_subnets = flatten([for t in var.cluster_subnet_tiers : var.subnet_ids_by_tier[t]])

  # Fargate profiles default to this tier unless a profile sets its own.
  fargate_tier = coalesce(var.fargate_subnet_tier, var.cluster_subnet_tiers[0])

  # Fargate is opt-in: setting fargate_profiles turns a plain EKS cluster into
  # an EKS-on-Fargate cluster. Node groups and mixed mode are added later via
  # their own toggles, letting the user move between modes without manual
  # destroys.
  create_fargate = length(var.fargate_profiles) > 0

  # Resolve each profile's subnet tier to concrete subnet IDs — the profile's
  # own subnet_tier when set, otherwise the default fargate_tier.
  fargate_profiles_resolved = [
    for p in var.fargate_profiles : {
      name               = p.name
      namespace          = p.namespace
      labels             = p.labels
      subnet_ids         = var.subnet_ids_by_tier[coalesce(p.subnet_tier, local.fargate_tier)]
      pod_execution_role = p.pod_execution_role
    }
  ]

  # Create a pod execution role for each distinct non-default key referenced by
  # a profile. The module always adds the "default" role on top of these.
  # Cross-account ECR pull policies are attached to a named role by the
  # eks-ecr-pull project, not here.
  pod_execution_roles = {
    for k in toset([for p in var.fargate_profiles : p.pod_execution_role if p.pod_execution_role != null]) :
    k => { additional_policy_arns = [] }
  }
}

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

module "fargate_profiles" {
  count  = local.create_fargate ? 1 : 0
  source = "../../../shared/modules/eks-fargate-profiles"

  cluster_name = module.cluster.cluster_name

  pod_execution_roles = local.pod_execution_roles
  fargate_profiles    = local.fargate_profiles_resolved
}
