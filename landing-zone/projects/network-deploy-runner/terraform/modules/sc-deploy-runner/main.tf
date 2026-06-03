locals {
  s3_source_bucket_param = var.s3_source_bucket != "" ? [{
    key   = "CBS3SourceBucket"
    value = var.s3_source_bucket
  }] : []

  caller_params = (var.caller_arn != "" && var.caller_account_id != "") ? [
    { key = "CallerARN", value = var.caller_arn },
    { key = "CallerAccountId", value = var.caller_account_id },
  ] : []
}

# Associate the Terraform execution role with the portfolio so it can call
# provision-product. The ORGANIZATION-level share is auto-imported into every
# account; no explicit accept-portfolio-share step is needed.
# Equivalent to associate-principal-with-portfolio in provision-product-operations.sh,
# where $BOOTSTRAP_CALLER_ARN is the role the script is running as after assuming
# AWSControlTowerExecution.
resource "aws_servicecatalog_principal_portfolio_association" "caller" {
  portfolio_id   = var.portfolio_id
  principal_arn  = var.terraform_role_arn
  principal_type = "IAM"
}

resource "aws_servicecatalog_provisioned_product" "this" {
  name    = var.provisioned_product_name

  # Use IDs rather than display names — stable, unambiguous, and resolved once
  # by bootstrap-parameters at pipeline run time.
  product_id               = var.product_id
  path_id                  = var.portfolio_id
  provisioning_artifact_id = var.provisioning_artifact_id

  # No lifecycle.ignore_changes on provisioning_artifact_id: the artifact ID is
  # an explicit pipeline input resolved by bootstrap-parameters. Updating to a
  # new product version is triggered by re-running the pipeline after a new
  # artifact is published — bootstrap-parameters picks up the latest DEFAULT
  # artifact and the changed ID causes Terraform to call update-provisioned-product.

  provisioning_parameters {
    key   = "ProjectName"
    value = var.cb_project_name
  }

  provisioning_parameters {
    key   = "CreateBucket"
    value = var.create_bucket ? "true" : "false"
  }

  dynamic "provisioning_parameters" {
    for_each = local.s3_source_bucket_param
    content {
      key   = provisioning_parameters.value.key
      value = provisioning_parameters.value.value
    }
  }

  dynamic "provisioning_parameters" {
    for_each = local.caller_params
    content {
      key   = provisioning_parameters.value.key
      value = provisioning_parameters.value.value
    }
  }

  depends_on = [
    aws_servicecatalog_principal_portfolio_association.caller,
  ]
}
