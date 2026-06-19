variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the CoreDNS add-on on."
}

variable "addon_version" {
  type        = string
  description = "Pinned CoreDNS managed add-on version (e.g. 'v1.11.4-eksbuild.40'). Null lets EKS pick the default version for the cluster's Kubernetes release. For EKS 1.32, use 'v1.11.4-eksbuild.40'."
  default     = null
}

variable "compute_type" {
  type        = string
  description = "Compute type CoreDNS pods are scheduled on. Set to 'Fargate' for pure-Fargate clusters (requires a kube-system Fargate profile). Leave null for EC2-based clusters to use the EKS default."
  default     = null

  validation {
    condition     = var.compute_type == null || contains(["Fargate"], var.compute_type)
    error_message = "compute_type must be null or 'Fargate'."
  }
}

variable "resolve_conflicts_on_create" {
  type        = string
  description = "How to resolve field-management conflicts when first creating the add-on over the self-managed CoreDNS that EKS installs by default."
  default     = "OVERWRITE"
}

variable "resolve_conflicts_on_update" {
  type        = string
  description = "How to resolve field-management conflicts on add-on updates. PRESERVE keeps any in-cluster customizations."
  default     = "PRESERVE"
}
