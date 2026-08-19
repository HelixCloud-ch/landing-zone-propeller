variable "region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed."
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Sourced from the eks-cluster project output."
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the IAM OIDC identity provider associated with the EKS cluster. Sourced from the eks-cluster project output. Required when use_pod_identity = false."
  default     = null

  validation {
    condition     = var.use_pod_identity || (var.oidc_provider_arn != null && length(var.oidc_provider_arn) > 0)
    error_message = "oidc_provider_arn is required when use_pod_identity = false."
  }
}

variable "oidc_provider_url" {
  type        = string
  description = "Issuer URL of the OIDC provider (without the https:// prefix). Sourced from the eks-cluster project output. Required when use_pod_identity = false."
  default     = null

  validation {
    condition     = var.use_pod_identity || (var.oidc_provider_url != null && length(var.oidc_provider_url) > 0)
    error_message = "oidc_provider_url is required when use_pod_identity = false."
  }
}

variable "use_pod_identity" {
  type        = bool
  description = "Whether to use EKS Pod Identity instead of IRSA/OIDC. vpc-cni supports both. Requires the eks-pod-identity-agent add-on to be installed. Default: false (uses IRSA/OIDC)."
  default     = false
}

variable "addon_version" {
  type        = string
  description = "Pinned version of the vpc-cni managed add-on (e.g. \"v1.19.5-eksbuild.1\"). Null lets EKS pick the default."
  default     = null
}

variable "configuration_values" {
  type        = string
  description = "JSON-encoded configuration_values for the vpc-cni add-on. Null uses EKS defaults."
  default     = null
}

variable "role_name" {
  type        = string
  description = "Name of the IRSA role for vpc-cni. Defaults to '<cluster_name>-vpc-cni'."
  default     = null
}

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
