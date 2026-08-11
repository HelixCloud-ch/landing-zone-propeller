variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the add-on on."
}

variable "addon_name" {
  type        = string
  description = "Name of the EKS add-on (e.g. 'vpc-cni', 'kube-proxy', 'eks-pod-identity-agent', 'aws-ebs-csi-driver')."
}

variable "addon_version" {
  type        = string
  description = "Pinned version of the add-on. Null resolves to the most recent compatible version for the cluster's Kubernetes release."
  default     = null
}

variable "resolve_conflicts_on_create" {
  type        = string
  description = "How to resolve field-management conflicts when creating the add-on."
  default     = "OVERWRITE"
}

variable "resolve_conflicts_on_update" {
  type        = string
  description = "How to resolve field-management conflicts on add-on updates."
  default     = "OVERWRITE"
}

variable "configuration_values" {
  type        = string
  description = "JSON-encoded configuration_values. Null uses EKS defaults. For non-trivial config, use a dedicated addon module instead."
  default     = null
}

variable "service_account_role_arn" {
  type        = string
  description = "ARN of an IAM role to bind to the add-on's service account. Null uses the node IAM role permissions."
  default     = null
}

variable "preserve" {
  type        = bool
  description = "Whether to preserve the add-on's resources when deleting from Terraform."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the add-on resource. Merged with provider default_tags."
  default     = {}
}
