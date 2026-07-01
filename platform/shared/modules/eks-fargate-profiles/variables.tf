# ── Cluster inputs (from eks-cluster outputs) ─────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Sourced from the eks-cluster module output."
}

# ── Pod execution roles ───────────────────────────────────────────────────────

variable "pod_execution_role_name" {
  type        = string
  description = "Name of the default Fargate pod execution IAM role (the 'default' key). Defaults to '<cluster_name>-fargate-pod-exec'. Named roles from pod_execution_roles are named '<cluster_name>-fargate-pod-exec-<key>'."
  default     = null
}

variable "pod_execution_roles" {
  type = map(object({
    arn                    = optional(string)
    additional_policy_arns = optional(list(string), [])
  }))
  description = "Named Fargate pod execution roles beyond the always-present 'default'. For each key: leave arn null to have this module create the role (base AmazonEKSFargatePodExecutionRolePolicy plus any additional_policy_arns), or set arn to consume an externally-managed role (e.g. centralized role management) — in which case the module creates nothing for that key. The 'default' key may be supplied here to externalize the default role too. Profiles reference a role by key via pod_execution_role; multiple profiles may share the same key."
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.pod_execution_roles :
      v.arn == null || length(v.additional_policy_arns) == 0
    ])
    error_message = "additional_policy_arns cannot be set on a role that supplies an external arn — the external role's owner manages its policies."
  }
}

# ── Fargate profiles ──────────────────────────────────────────────────────────

variable "fargate_profiles" {
  type = list(object({
    name               = string
    namespace          = string
    labels             = optional(map(string), {})
    subnet_ids         = list(string)
    pod_execution_role = optional(string)
  }))
  description = "Fargate profiles to create. Each entry produces one aws_eks_fargate_profile with a single selector and its own subnet_ids (private subnets with a route to the cluster API endpoint). pod_execution_role selects which role (a key in pod_execution_roles, or the implicit 'default') the profile assumes; profiles sharing a role reference the same key. Different profiles may target different subnets — e.g. a team with a dedicated subnet. Use multiple entries with the same namespace but different labels for more granular pod scheduling. Default is empty — callers opt in to the namespaces they need."
  default     = []
}
