module "deploy_runners" {
  source   = "../../../shared/modules/sc-deploy-runner"
  for_each = var.account_ids

  providers = {
    aws = aws.notags
  }

  portfolio_id             = var.portfolio_id
  product_id               = var.product_id
  provisioning_artifact_id = var.provisioning_artifact_id
  provisioned_product_name = "deploy-runner"

  terraform_role_arn = "arn:aws:iam::${each.value}:role/${var.assume_role_name}"

  cb_project_name   = "deploy-runner"
  create_bucket     = true
  s3_source_bucket  = var.s3_source_bucket
  caller_arn        = var.caller_arn
  caller_account_id = var.caller_account_id

  tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
}
