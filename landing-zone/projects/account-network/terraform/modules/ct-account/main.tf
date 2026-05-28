locals {
  managed_organizational_unit = "${var.ou_name} (${var.ou_id})"
}
resource "aws_servicecatalog_provisioned_product" "this" {
  name                       = var.account_name
  product_name               = var.product_name
  path_name                  = var.portfolio_path_name
  provisioning_artifact_name = var.provisioning_artifact_name
  retain_physical_resources  = true # never close the AWS account on Terraform destroy

  provisioning_parameters {
    key   = "AccountName"
    value = var.account_name
  }

  provisioning_parameters {
    key                = "AccountEmail"
    value              = var.account_email
    use_previous_value = true
  }

  provisioning_parameters {
    key   = "SSOUserEmail"
    value = var.sso_user_email
  }

  provisioning_parameters {
    key   = "SSOUserFirstName"
    value = var.sso_user_first_name
  }

  provisioning_parameters {
    key   = "SSOUserLastName"
    value = var.sso_user_last_name
  }

  provisioning_parameters {
    key   = "ManagedOrganizationalUnit"
    value = local.managed_organizational_unit
  }

  lifecycle {
    ignore_changes = [
      name,
      provisioning_artifact_name,
      provisioning_artifact_id,
    ]
  }
}
