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
  description = "ARN of an IRSA role to bind to the add-on's service account. Null uses the node IAM role permissions. Mutually exclusive with pod_identity_association."
  default     = null
}

variable "pod_identity_association" {
  type = object({
    role_arn        = string
    service_account = string
  })
  description = "EKS Pod Identity association for the add-on, as an alternative to IRSA. Null (default) does not configure Pod Identity. Mutually exclusive with service_account_role_arn."
  default     = null

  validation {
    condition     = var.pod_identity_association == null || var.service_account_role_arn == null
    error_message = "pod_identity_association and service_account_role_arn are mutually exclusive; set at most one."
  }
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
