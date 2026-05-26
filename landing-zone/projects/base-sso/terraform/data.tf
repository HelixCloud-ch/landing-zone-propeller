data "aws_ssoadmin_instances" "this" {}

data "aws_caller_identity" "this" {}

locals {
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
}

# When using an external IdP, look up the IdentityOperators group that SCIM
# has already created. This will fail at plan time if the group does not yet
# exist — by design.
data "aws_identitystore_group" "identity_operators" {
  count             = var.external_idp ? 1 : 0
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = var.identity_operators_group_name
    }
  }
}
