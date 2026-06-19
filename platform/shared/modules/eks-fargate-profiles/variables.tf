# ── Cluster inputs (from eks-cluster outputs) ─────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Sourced from the eks-cluster module output."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs to place Fargate workloads in. Must be private subnets with route to the cluster API endpoint."
}

# ── Fargate profiles ──────────────────────────────────────────────────────────

variable "pod_execution_role_name" {
  type        = string
  description = "Name of the Fargate pod execution IAM role. Defaults to '<cluster_name>-fargate-pod-exec'."
  default     = null
}

variable "fargate_profiles" {
  type = list(object({
    name      = string
    namespace = string
    labels    = optional(map(string), {})
  }))
  description = "Fargate profiles to create. Each entry produces one aws_eks_fargate_profile with a single selector. Use multiple entries with the same namespace but different labels for more granular pod scheduling. Default is empty — callers opt-in to the namespaces they need."
  default     = []
}
