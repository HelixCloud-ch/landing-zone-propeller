# ── Permission sets ──────────────────────────────────────────────────────────
# Permission set names are singular. Groups are plural.

resource "aws_ssoadmin_permission_set" "readonly" {
  instance_arn     = local.instance_arn
  name             = "ReadOnly"
  description      = "Read-only access to all AWS services and resources."
  session_duration = var.session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly" {
  instance_arn       = local.instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.readonly.arn
}

resource "aws_ssoadmin_permission_set" "poweruser" {
  instance_arn     = local.instance_arn
  name             = "PowerUser"
  description      = "Power user access (manage AWS resources, no IAM/Organizations management)."
  session_duration = var.session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "poweruser" {
  instance_arn       = local.instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
  permission_set_arn = aws_ssoadmin_permission_set.poweruser.arn
}

resource "aws_ssoadmin_permission_set" "admin" {
  instance_arn     = local.instance_arn
  name             = "Admin"
  description      = "Full administrative access."
  session_duration = var.session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = local.instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
}

# IdentityOperator: manages permission set assignments. Cannot create
# permission sets (the inline policy doesn't allow it and AWSSSOReadOnly is
# read-only on permission sets), but can assign any of them — including
# IdentityOperator itself. Recovery from accidental misconfiguration is a
# simple re-apply of this project.
resource "aws_ssoadmin_permission_set" "identity_operator" {
  instance_arn     = local.instance_arn
  name             = "IdentityOperator"
  description      = "Manage IAM Identity Center user/group assignments to AWS accounts."
  session_duration = var.session_duration
}

# AWSSSOReadOnly — full read on sso:*, plus required reads on Directory
# Service, IAM, Organizations, KMS. Console-friendly without whack-a-mole.
resource "aws_ssoadmin_managed_policy_attachment" "identity_operator_sso_read" {
  instance_arn       = local.instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AWSSSOReadOnly"
  permission_set_arn = aws_ssoadmin_permission_set.identity_operator.arn
}

# Directory access. Local mode: full admin (create users/groups/MFA).
# External-IdP mode: read-only (writes would be overwritten by SCIM sync).
resource "aws_ssoadmin_managed_policy_attachment" "identity_operator_directory" {
  instance_arn = local.instance_arn
  managed_policy_arn = (
    var.external_idp
    ? "arn:aws:iam::aws:policy/AWSSSODirectoryReadOnly"
    : "arn:aws:iam::aws:policy/AWSSSODirectoryAdministrator"
  )
  permission_set_arn = aws_ssoadmin_permission_set.identity_operator.arn
}

# Inline policy for IdentityOperator:
# - allow assignment writes (Create/Delete/ProvisionPermissionSet)
# - allow IAM on sso-reserved roles (required for assignments)
# - allow PassRole to sso.amazonaws.com
resource "aws_ssoadmin_permission_set_inline_policy" "identity_operator" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.identity_operator.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteAssignments"
        Effect = "Allow"
        Action = [
          "sso:AssociateProfile",
          "sso:CreateAccountAssignment",
          "sso:DeleteAccountAssignment",
          "sso:DisassociateProfile",
          "sso:ProvisionPermissionSet",
        ]
        Resource = "*"
      },
      {
        # IC creates these IAM roles in target accounts on assignment.
        # Two ARN patterns: member accounts use the /aws-reserved/sso.amazonaws.com/
        # path; the management account (where IC lives) uses the flat AWSReservedSSO_ prefix.
        Sid    = "ManageSSOReservedRoles"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:GetRole",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:PutRolePolicy",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
        ]
        Resource = [
          "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*",
          "arn:aws:iam::*:role/AWSReservedSSO_*",
        ]
      },
      {
        Sid      = "PassRoleForSso"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "sso.amazonaws.com"
          }
        }
      },
      {
        Sid    = "ReadSAMLProvider"
        Effect = "Allow"
        Action = "iam:GetSAMLProvider"
        Resource = "arn:aws:iam::*:saml-provider/AWSSSO_*_DO_NOT_DELETE"
      },
    ]
  })
}

# ── IdentityOperators group ──────────────────────────────────────────────────
# Local mode: created here. External-IdP mode: looked up via data source.

resource "aws_identitystore_group" "identity_operators" {
  count             = var.external_idp ? 0 : 1
  identity_store_id = local.identity_store_id
  display_name      = var.identity_operators_group_name
  description       = "Members get the IdentityOperator permission set, allowing them to manage assignments for the other base permission sets (ReadOnly, PowerUser, Admin)."
}

locals {
  identity_operators_group_id = (
    var.external_idp
    ? data.aws_identitystore_group.identity_operators[0].group_id
    : aws_identitystore_group.identity_operators[0].group_id
  )
}

# ── Pre-assignment ───────────────────────────────────────────────────────────
# Pre-assign IdentityOperator to the aws-identity-operators group on the
# current account (typically the management account, where this project
# runs). Once a member is added to the group (manually or via SCIM), they
# can immediately start managing assignments for other accounts.

resource "aws_ssoadmin_account_assignment" "identity_operator_self" {
  instance_arn = local.instance_arn

  permission_set_arn = aws_ssoadmin_permission_set.identity_operator.arn

  principal_id   = local.identity_operators_group_id
  principal_type = "GROUP"

  target_id   = data.aws_caller_identity.this.account_id
  target_type = "AWS_ACCOUNT"
}
