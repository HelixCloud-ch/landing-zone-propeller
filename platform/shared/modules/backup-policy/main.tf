data "aws_partition" "current" {}

# Every leaf value in an Organizations backup policy is wrapped in an
# "@@assign" inheritance operator, and numbers are passed as strings.
locals {
  plan_name = coalesce(var.plan_name, var.name)

  windows = merge(
    var.start_window_minutes == null ? {} : { start_backup_window_minutes = { "@@assign" = tostring(var.start_window_minutes) } },
    var.completion_window_minutes == null ? {} : { complete_backup_window_minutes = { "@@assign" = tostring(var.completion_window_minutes) } },
  )

  # The copy action carries its own lifecycle, so the short source retention
  # does not propagate to the copy.
  copy_actions = var.copy_vault_arn == null ? {} : {
    copy_actions = {
      (var.copy_vault_arn) = {
        target_backup_vault_arn = { "@@assign" = var.copy_vault_arn }
        lifecycle               = { delete_after_days = { "@@assign" = tostring(var.copy_retention_days) } }
      }
    }
  }

  rule = merge(
    {
      schedule_expression      = { "@@assign" = var.schedule_expression }
      target_backup_vault_name = { "@@assign" = var.source_vault_name }
      lifecycle                = { delete_after_days = { "@@assign" = tostring(var.source_retention_days) } }
    },
    local.windows,
    local.copy_actions,
  )

  policy = {
    plans = {
      (local.plan_name) = {
        regions = { "@@assign" = var.regions }
        rules   = { (var.rule_name) = local.rule }
        selections = {
          tags = {
            (var.rule_name) = {
              # $account is a literal placeholder that Organizations resolves
              # per receiving account; a literal account ID is rejected.
              iam_role_arn = { "@@assign" = "arn:${data.aws_partition.current.partition}:iam::$account:role/${var.iam_role_name}" }
              tag_key      = { "@@assign" = var.selection_tag_key }
              tag_value    = { "@@assign" = var.selection_tag_values }
            }
          }
        }
      }
    }
  }
}

resource "aws_organizations_policy" "this" {
  name        = var.name
  type        = "BACKUP_POLICY"
  description = var.description
  content     = jsonencode(local.policy)
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = toset(var.target_ids)

  policy_id = aws_organizations_policy.this.id
  target_id = each.value
}
