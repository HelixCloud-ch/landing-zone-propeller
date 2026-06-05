locals {
  terraform_role_arn = "arn:aws:iam::${var.network_account_id}:role/${var.assume_role_name}"
}

module "deploy_runner" {
  source = "../../../shared/modules/sc-deploy-runner"

  portfolio_id             = var.portfolio_id
  product_id               = var.product_id
  provisioning_artifact_id = var.provisioning_artifact_id
  terraform_role_arn       = local.terraform_role_arn
  provisioned_product_name = var.provisioned_product_name

  cb_project_name   = var.cb_project_name
  create_bucket     = var.create_bucket
  s3_source_bucket  = var.s3_source_bucket
  caller_arn        = var.caller_arn
  caller_account_id = var.caller_account_id

  tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
}
