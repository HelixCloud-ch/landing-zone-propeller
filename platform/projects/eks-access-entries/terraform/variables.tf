# ── Region ────────────────────────────────────────────────────────────────────

variable "region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed."
}

# ── Pipeline input (from eks-cluster outputs) ─────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Sourced from the eks-cluster project output."
}

# ── SSO-discovered entries ────────────────────────────────────────────────────
# IAM Identity Center creates roles named AWSReservedSSO_<PermissionSetName>_<suffix>.
# The suffix is not predictable and changes if the assignment is deleted and recreated.
# This project discovers the ARN at plan time via data.aws_iam_roles; no ARN
# needs to be hardcoded by the consumer.
#
# Each entry maps an arbitrary key (used as the Terraform resource key) to:
#   permission_set_name : the IAM Identity Center permission set name to look up
#   policy_arn          : the EKS cluster-access policy ARN to associate
#
# Reference:
# https://docs.aws.amazon.com/singlesignon/latest/userguide/referencingpermissionsets.html

variable "sso_access_entries" {
  type = map(object({
    permission_set_name = string
    policy_arns         = list(string)
  }))
  description = <<-EOT
    Map of key → { permission_set_name, policy_arns } for IAM Identity Center
    permission sets. For each entry the project discovers the AWSReservedSSO_*
    role in this account and registers it as an EKS access entry, associating
    all listed cluster-access policies (permissions are additive).

    If a permission set has not been assigned to this account yet, the role is
    not found and the entry is silently skipped — no error, no drift.

    For available policy ARNs and their Kubernetes permissions see:
    https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html

    Note: AWS does not support custom access policies. For custom Kubernetes
    RBAC, specify group names on the access entry and manage ClusterRole /
    ClusterRoleBinding objects directly.
  EOT
  default = {
    readonly = {
      permission_set_name = "ReadOnly"
      policy_arns         = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"]
    }
    poweruser = {
      permission_set_name = "PowerUser"
      policy_arns         = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"]
    }
    admin = {
      permission_set_name = "Admin"
      policy_arns         = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"]
    }
  }
}

variable "sso_region" {
  type        = string
  description = "AWS region where IAM Identity Center is homed. Used to construct the path prefix for AWSReservedSSO_* role lookup. For us-east-1 the path prefix omits the region; for all other regions it is /aws-reserved/sso.amazonaws.com/<sso_region>/."
}

# ── Direct ARN entries ────────────────────────────────────────────────────────
# For IAM principals (roles or users) whose ARN is already known — e.g. a CI/CD
# service role, an IAM user used for break-glass access, or a cross-account role.
# These bypass the SSO role discovery path entirely.

variable "direct_access_entries" {
  type = map(object({
    principal_arn = string
    policy_arns   = list(string)
  }))
  description = <<-EOT
    Map of key → { principal_arn, policy_arns } for IAM principals whose ARN is
    known directly (not discovered via IAM Identity Center). Accepts both role
    ARNs (arn:aws:iam::<id>:role/<name>) and user ARNs (...:user/<name>).
    Use for CI/CD service roles, break-glass IAM users, or cross-account roles.

    For available policy ARNs see:
    https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html
  EOT
  default = {}
}

# ── Tagging ────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Base tags merged into the provider default_tags block."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Consumer-specific tags merged into the provider default_tags block."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Propeller framework tags merged into the provider default_tags block."
  default     = {}
}
