# Provisioned product names must be unique in the management account; the
# suffix is stable for the lifetime of the map key (see workload-accounts).
resource "random_id" "account_suffix" {
  for_each = var.accounts

  keepers     = { account_name = each.key }
  byte_length = 4
}

module "accounts" {
  source   = "../../../shared/modules/ct-account"
  for_each = var.accounts

  providers = {
    aws = aws.notags
  }

  account_name             = each.key
  provisioned_product_name = "${each.key}-${random_id.account_suffix[each.key].hex}"
  account_email            = each.value.email

  ou_name = var.infrastructure_ou_name
  ou_id   = var.infrastructure_ou_id

  sso_user_email      = coalesce(each.value.sso_user_email, each.value.email)
  sso_user_first_name = each.value.sso_user_first_name
  sso_user_last_name  = each.value.sso_user_last_name
}
