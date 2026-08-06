locals {
  s3_read_buckets_param = var.s3_source_bucket != "" ? [{
    key   = "S3ReadBuckets"
    value = var.s3_source_bucket
  }] : []

  caller_params = (var.caller_arn != "" && var.caller_account_id != "") ? [
    { key = "CallerARN", value = var.caller_arn },
    { key = "CallerAccountId", value = var.caller_account_id },
  ] : []
}

resource "aws_servicecatalog_principal_portfolio_association" "caller" {
  portfolio_id   = var.portfolio_id
  principal_arn  = var.terraform_role_arn
  principal_type = "IAM"
}

resource "aws_servicecatalog_provisioned_product" "this" {
  name                     = var.provisioned_product_name
  product_id               = var.product_id
  provisioning_artifact_id = var.provisioning_artifact_id
  tags                     = var.tags

  provisioning_parameters {
    key   = "ProjectName"
    value = var.cb_project_name
  }

  provisioning_parameters {
    key   = "CreateBucket"
    value = var.create_bucket ? "true" : "false"
  }

  dynamic "provisioning_parameters" {
    for_each = local.s3_read_buckets_param
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

  depends_on = [aws_servicecatalog_principal_portfolio_association.caller]
}
