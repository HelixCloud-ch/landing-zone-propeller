module "coredns" {
  count  = var.install_coredns ? 1 : 0
  source = "../../../shared/modules/eks-addon-coredns"

  cluster_name  = var.cluster_name
  addon_version = var.coredns_version
  compute_type  = var.coredns_compute_type
}

module "base_addon" {
  for_each = { for k, v in var.base_addons : k => v if v.enabled }
  source   = "../../../shared/modules/eks-addon-base"

  cluster_name             = var.cluster_name
  addon_name               = each.key
  addon_version            = each.value.version
  configuration_values     = each.value.configuration_values
  service_account_role_arn = each.value.service_account_role_arn
}
