# ── Provision deploy-runner into each workload account ─────────────────────────
#
# Service Catalog provision-product must be called from inside the target
# account. Terraform providers are static — can't dynamically vary assume_role
# per for_each iteration. We use terraform_data + local-exec to assume into
# each account and run the provisioning logic.
#
# State tracks which accounts have been provisioned. Re-triggers when any
# input changes (new artifact, new account, etc).

resource "terraform_data" "deploy_runner" {
  for_each = var.account_ids

  input = {
    account_id               = each.value
    region                   = var.region
    assume_role_name         = var.assume_role_name
    portfolio_id             = var.portfolio_id
    product_id               = var.product_id
    provisioning_artifact_id = var.provisioning_artifact_id
    s3_source_bucket         = var.s3_source_bucket
    caller_arn               = var.caller_arn
    caller_account_id        = var.caller_account_id
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/provision-deploy-runner.sh"
    environment = {
      ACCOUNT_ID               = each.value
      ACCOUNT_NAME             = each.key
      AWS_REGION               = var.region
      ASSUME_ROLE_NAME         = var.assume_role_name
      PORTFOLIO_ID             = var.portfolio_id
      PRODUCT_ID               = var.product_id
      PROVISIONING_ARTIFACT_ID = var.provisioning_artifact_id
      S3_SOURCE_BUCKET         = var.s3_source_bucket
      CALLER_ARN               = var.caller_arn
      CALLER_ACCOUNT_ID        = var.caller_account_id
      PROVISIONED_PRODUCT_NAME = "deploy-runner"
      CB_PROJECT_NAME          = "deploy-runner"
    }
  }
}
