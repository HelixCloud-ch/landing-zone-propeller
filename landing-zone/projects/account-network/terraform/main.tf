locals {
  sso_user_email = var.sso_user_email != "" ? var.sso_user_email : var.account_email
}

module "account" {
  source = "../../../shared/modules/ct-account"

  providers = {
    aws = aws.notags
  }

  account_name  = var.account_name
  account_email = var.account_email

  ou_name = var.ou_name
  ou_id   = var.ou_id

  sso_user_email      = local.sso_user_email
  sso_user_first_name = var.sso_user_first_name
  sso_user_last_name  = var.sso_user_last_name
}
