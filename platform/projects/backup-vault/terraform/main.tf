data "aws_caller_identity" "current" {}

module "vault" {
  source = "../../../shared/modules/backup-vault"

  name            = var.vault_name
  kms_key_arn     = var.kms_key_arn
  kms_key_alias   = var.kms_key_alias
  vault_lock      = var.vault_lock
  role_name       = var.role_name
  enable_restores = var.enable_restores

  # peer_account_id is the single-value form a pipeline input can fill.
  cross_account_access = {
    account_ids     = distinct(compact(concat([var.peer_account_id], var.peer_account_ids)))
    organization_id = var.organization_id
    org_paths       = var.org_paths
  }
}
