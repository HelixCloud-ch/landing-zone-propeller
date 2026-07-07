# ── SSO role discovery ────────────────────────────────────────────────────────
# IAM Identity Center creates a role named AWSReservedSSO_<PermissionSetName>_<random-suffix>
# in each member account when a permission set is assigned. The suffix is not
# predictable and changes if the assignment is ever deleted and recreated.
# We discover the ARN dynamically using aws_iam_roles filtered by name_regex and
# path_prefix so the consumer never needs to hardcode the suffix.
#
# If a permission set has not been assigned to this account yet, the data source
# returns an empty set and the entry is silently skipped — no error, no drift.
#
# Reference:
# https://docs.aws.amazon.com/singlesignon/latest/userguide/referencingpermissionsets.html

locals {
  # IAM Identity Center roles live under /aws-reserved/sso.amazonaws.com/ in
  # member accounts. For Identity Center homed in us-east-1 there is no region
  # segment; for all other regions it is appended.
  sso_path_prefix = (
    var.sso_region == "us-east-1"
    ? "/aws-reserved/sso.amazonaws.com/"
    : "/aws-reserved/sso.amazonaws.com/${var.sso_region}/"
  )
}

# One data source per SSO entry — discovers the AWSReservedSSO_* role ARN.
data "aws_iam_roles" "sso" {
  for_each = var.sso_access_entries

  name_regex  = "^AWSReservedSSO_${each.value.permission_set_name}_[0-9a-f]{16}$"
  path_prefix = local.sso_path_prefix
}

locals {
  # SSO entries: keep only those where the role was actually found in this account.
  # Keys are namespaced with "sso_" to avoid collisions with direct entries.
  resolved_sso_entries = {
    for k, v in var.sso_access_entries :
    "sso_${k}" => {
      principal_arn = tolist(data.aws_iam_roles.sso[k].arns)[0]
      policy_arns   = v.policy_arns
    }
    if length(data.aws_iam_roles.sso[k].arns) > 0
  }

  # Direct entries: ARN is already known, no discovery needed.
  # Keys are namespaced with "direct_" to avoid collisions with SSO keys.
  resolved_direct_entries = {
    for k, v in var.direct_access_entries :
    "direct_${k}" => {
      principal_arn = v.principal_arn
      policy_arns   = v.policy_arns
    }
  }

  # Merged map of all access entries keyed by namespaced key.
  all_entries = merge(local.resolved_sso_entries, local.resolved_direct_entries)

  # Flat map for policy associations: one entry per (access-entry, policy) pair.
  # Key format: "<entry_key>__<policy_arn>" — the double underscore avoids any
  # collision since neither ARNs nor our entry keys contain double underscores.
  all_policy_associations = {
    for pair in flatten([
      for entry_key, entry in local.all_entries : [
        for policy_arn in entry.policy_arns : {
          key           = "${entry_key}__${policy_arn}"
          entry_key     = entry_key
          principal_arn = entry.principal_arn
          policy_arn    = policy_arn
        }
      ]
    ]) : pair.key => pair
  }
}

# ── EKS access entries ────────────────────────────────────────────────────────

resource "aws_eks_access_entry" "this" {
  for_each = local.all_entries

  cluster_name  = var.cluster_name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "this" {
  for_each = local.all_policy_associations

  cluster_name  = var.cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.this]
}
