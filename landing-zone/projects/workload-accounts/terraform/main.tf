# ── Validation ────────────────────────────────────────────────────────────────

locals {
  collisions = setintersection(keys(var.accounts), var.reserved_account_names)
}

resource "terraform_data" "validate_account_names" {
  lifecycle {
    precondition {
      condition     = length(local.collisions) == 0
      error_message = "Account names collide with reserved governance names: ${join(", ", local.collisions)}. Choose different names or adjust reserved_account_names."
    }
  }
}

# ── Accounts ──────────────────────────────────────────────────────────────────

module "accounts" {
  source   = "../../../shared/modules/ct-account"
  for_each = var.accounts

  account_name  = each.key
  account_email = each.value.email

  ou_name = element(split("/", each.value.ou), length(split("/", each.value.ou)) - 1)
  ou_id   = var.ou_ids[each.value.ou]

  sso_user_email      = coalesce(each.value.sso_user_email, each.value.email)
  sso_user_first_name = each.value.sso_user_first_name
  sso_user_last_name  = each.value.sso_user_last_name

  depends_on = [terraform_data.validate_account_names]
}

# ── Account registry ──────────────────────────────────────────────────────────
# These SSM parameters are the contract between the landing zone and platform
# pipelines. A platform pipeline targets an account by name (e.g. target:
# acme-prod); the engine resolves it by reading /propeller/accounts/<name>/id.
# They are created directly here because the list is dynamic, and because we are
# satisfying an actual contract, pre-requisite of the Platform pipelines.

resource "aws_ssm_parameter" "account_ids" {
  for_each = module.accounts

  name      = "/propeller/accounts/${replace(each.key, " ", "-")}/id"
  type      = "String"
  value     = each.value.account_id
  overwrite = true
}
