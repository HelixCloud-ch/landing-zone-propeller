# ── Cluster reference ──────────────────────────────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster this node group belongs to."

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

# ── Node groups ───────────────────────────────────────────────────────────────

variable "node_groups" {
  type = list(object({
    name            = string
    node_role_arn   = string
    subnet_ids      = list(string)
    instance_types  = optional(list(string), ["t3.medium"])
    capacity_type   = optional(string, "ON_DEMAND")
    ami_type        = optional(string, "AL2023_x86_64_STANDARD")
    release_version = optional(string)
    disk_size       = optional(number)
    desired_size    = optional(number, 2)
    min_size        = optional(number, 1)
    max_size        = optional(number, 10)
    max_unavailable = optional(number, 1)
    labels          = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    launch_template_id      = optional(string)
    launch_template_version = optional(string, "$Latest")
  }))
  description = "List of managed node groups to create. Each entry produces one aws_eks_node_group with its own scaling config, instance types, and labels/taints. The node_role_arn and subnet_ids are resolved by the calling project."
  default     = []
}
