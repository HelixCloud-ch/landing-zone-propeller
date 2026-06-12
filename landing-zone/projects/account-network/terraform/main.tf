locals {
  sso_user_email = var.sso_user_email != "" ? var.sso_user_email : var.account_email
}

# ── Stable unique suffix ───────────────────────────────────────────────────────
#
# Service Catalog requires provisioned product names to be unique within the
# management account. random_id with keepers = { account_name } is stable across
# plans for the lifetime of this state. Existing provisioned products are
# unaffected: ignore_changes = [name] is set on the resource in ct-account.
#
# Format: "<account-name>-<8-hex-chars>"
resource "random_id" "account_suffix" {
  keepers     = { account_name = var.account_name }
  byte_length = 4 # 8 hex chars
}

module "account" {
  source = "../../../shared/modules/ct-account"

  providers = {
    aws = aws.notags
  }

  account_name             = var.account_name
  provisioned_product_name = "${replace(var.account_name, " ", "-")}-${random_id.account_suffix.hex}"
  account_email            = var.account_email

  ou_name = var.ou_name
  ou_id   = var.ou_id

  sso_user_email      = local.sso_user_email
  sso_user_first_name = var.sso_user_first_name
  sso_user_last_name  = var.sso_user_last_name
}
