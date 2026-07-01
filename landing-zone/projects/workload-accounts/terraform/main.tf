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

# ── Stable unique suffix per account ──────────────────────────────────────────
#
# Service Catalog requires provisioned product names to be unique within the
# management account (max 128 chars, pattern [a-zA-Z0-9][a-zA-Z0-9._-]*).
# Deriving the name from account_name alone causes a collision when two accounts
# in different OUs share the same name.
#
# random_id with keepers = { account_name } generates an 8-char hex suffix that
# is stable across plans for the lifetime of the Terraform state. The suffix only
# regenerates if the map key is removed and re-added, which is a new account in
# practice. Existing provisioned products are unaffected: ignore_changes = [name]
# is set on the aws_servicecatalog_provisioned_product resource in ct-account.
#
# Format: "<account-name>-<8-hex-chars>"  (max: 50 + 1 + 8 = 59 chars < 128)
resource "random_id" "account_suffix" {
  for_each    = var.accounts
  keepers     = { account_name = each.key }
  byte_length = 4 # 8 hex chars
}

# ── Accounts ──────────────────────────────────────────────────────────────────

module "accounts" {
  source   = "../../../shared/modules/ct-account"
  for_each = var.accounts

  account_name             = each.key
  provisioned_product_name = "${replace(each.key, " ", "-")}-${random_id.account_suffix[each.key].hex}"
  account_email            = each.value.email

  ou_name = element(split("/", each.value.ou), length(split("/", each.value.ou)) - 1)
  ou_id   = var.ou_ids[each.value.ou]

  sso_user_email      = coalesce(each.value.sso_user_email, each.value.email)
  sso_user_first_name = each.value.sso_user_first_name
  sso_user_last_name  = each.value.sso_user_last_name

  depends_on = [terraform_data.validate_account_names]
}
