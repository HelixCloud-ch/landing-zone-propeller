locals {
  # Account Factory expects ManagedOrganizationalUnit in the form
  # "<OU name> (<OU id>)". This matches the format the AWS console displays
  # and the format the legacy ous module used.
  managed_organizational_unit = "${var.ou_name} (${var.ou_id})"
}

# Service Catalog provisioned product against the Control Tower Account
# Factory. Provisioning is synchronous from Terraform's perspective: the
# resource only completes once the provisioned product reaches AVAILABLE,
# which means the account has been created AND fully enrolled in CT (all
# baseline StackSets deployed). Downstream pipeline steps therefore run
# against a fully enrolled account, with no race condition on CT enrollment.
#
# See ADR-006 for the rationale on choosing Service Catalog over
# aws_organizations_account + auto-enrollment for account vending.
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

  # AccountEmail cannot be changed after creation. use_previous_value lets
  # Terraform leave the value alone on subsequent applies, which protects
  # against accidental edits to the tfvars file.
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
      # The provisioned product name drifts after CT renames it internally.
      name,

      # AWS publishes new provisioning artifact versions periodically. Without
      # ignore_changes, every existing provisioned product would show drift on
      # plan and Terraform would attempt to update them all. Migrations to a
      # newer artifact happen through a dedicated chore project (see
      # operations/account-vending.md).
      provisioning_artifact_name,
      provisioning_artifact_id,
    ]
  }
}
