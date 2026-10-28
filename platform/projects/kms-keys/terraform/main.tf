locals {
  # Names normalized like workload-account-registry, so shared_with uses the
  # same names as pipeline targets.
  account_ids = merge(
    { for n, id in var.workload_account_ids : lower(replace(n, " ", "-")) => id },
    { for n, id in var.landing_zone_account_ids : lower(replace(n, " ", "-")) => id },
  )

  keys = {
    for name, k in var.keys : name => merge(k, {
      alias       = coalesce(k.alias, "propeller/${name}")
      description = coalesce(k.description, "Customer managed key ${name}, managed by propeller.")
      cross_account_access = {
        account_ids     = distinct(concat([for n in k.shared_with : local.account_ids[n]], k.account_ids))
        organization_id = k.share_with_organization ? var.organization_id : null
        org_paths       = k.org_paths
      }
    })
  }
}

module "policy" {
  source   = "../../../shared/modules/backup-kms-key-policy"
  for_each = local.keys

  cross_account_access = each.value.cross_account_access
}

module "keys" {
  source   = "../../../shared/modules/kms-key"
  for_each = local.keys

  description             = each.value.description
  alias                   = each.value.alias
  policy_json             = module.policy[each.key].json
  enable_rotation         = each.value.enable_rotation
  rotation_period_in_days = each.value.rotation_period_in_days
  deletion_window_in_days = each.value.deletion_window_in_days
}
