locals {
  managed_organizational_unit = "${var.ou_name} (${var.ou_id})"
  # Spaces replaced with hyphens to satisfy the API pattern [a-zA-Z0-9][a-zA-Z0-9._-]*.
  # Uniqueness and overall length are the caller's responsibility.
  provisioned_product_name = replace(var.provisioned_product_name, " ", "-")
}
resource "aws_servicecatalog_provisioned_product" "this" {
  name                       = local.provisioned_product_name
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
      # The CT Account Factory blocks all tag mutations after provisioning
      # (Resource Update Constraint). Existing provisioned products carry tags
      # baked in at their original provision that can never be removed. Ignore
      # tag drift so Terraform never attempts an UpdateProvisionedProduct for
      # tags, which would fail with a ValidationException.
      tags,
      tags_all,
    ]
  }
}
