# The assume-role and provisioning logic lives in a local-exec script because
# terraform providers can't take an assume_role from an input at apply time.
# State re-runs the script when any input changes.

resource "terraform_data" "deploy_runner" {
  input = {
    account_id               = var.account_id
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
      ACCOUNT_ID               = var.account_id
      ACCOUNT_NAME             = var.account_name
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
