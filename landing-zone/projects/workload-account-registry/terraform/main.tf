# Writes /propeller/accounts/<name>/id for each workload account.
# These parameters are the contract that allows the autopilot Lambda to
# resolve platform pipeline targets (e.g. target: test-acc-1) to account IDs.

resource "aws_ssm_parameter" "account_ids" {
  for_each = var.account_ids

  name      = "/propeller/accounts/${lower(replace(each.key, " ", "-"))}/id"
  type      = "String"
  value     = each.value
  overwrite = true
}
