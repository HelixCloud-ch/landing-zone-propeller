locals {
  # OU paths (workload-parameters.ou_ids keys) resolved to IDs, plus raw IDs;
  # the per-policy copy vault falls back to the pipeline-wired one.
  policies = {
    for name, p in var.policies : name => merge(p, {
      target_ids     = distinct(concat([for path in p.target_ou_paths : var.ou_ids[path]], p.target_ids))
      regions        = length(p.regions) > 0 ? p.regions : [var.region]
      copy_vault_arn = p.copy_to_vault ? coalesce(p.copy_vault_arn, var.copy_vault_arn) : null
    })
  }
}

module "backup_policy" {
  source   = "../../../shared/modules/backup-policy"
  for_each = local.policies

  name                      = each.key
  description               = each.value.description
  target_ids                = each.value.target_ids
  regions                   = each.value.regions
  schedule_expression       = each.value.schedule_expression
  start_window_minutes      = each.value.start_window_minutes
  completion_window_minutes = each.value.completion_window_minutes
  source_vault_name         = each.value.source_vault_name
  source_retention_days     = each.value.source_retention_days
  iam_role_name             = each.value.iam_role_name
  copy_vault_arn            = each.value.copy_vault_arn
  copy_retention_days       = each.value.copy_vault_arn == null ? null : each.value.copy_retention_days
  selection_tag_key         = each.value.selection_tag_key
  selection_tag_values      = each.value.selection_tag_values
}
