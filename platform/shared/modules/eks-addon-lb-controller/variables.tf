variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the controller manages load balancers for."
}

variable "region" {
  type        = string
  description = "AWS region of the cluster. Passed to the controller as the 'region' Helm value."
}

variable "vpc_id" {
  type        = string
  description = "ID of the cluster VPC. Passed to the controller as the 'vpcId' Helm value."
}

variable "use_pod_identity" {
  type        = bool
  description = "Whether to use EKS Pod Identity instead of IRSA/OIDC for IAM credentials. Set to true for clusters with the Pod Identity Agent add-on."
  default     = false
}

# ── OIDC provider (required only when use_pod_identity = false) ───────────────

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster IAM OIDC provider. Required only when use_pod_identity = false. Used as the IRSA trust principal for the controller's service account role."
  default     = null

  validation {
    condition     = var.use_pod_identity || (var.oidc_provider_arn != null && length(var.oidc_provider_arn) > 0)
    error_message = "oidc_provider_arn is required when use_pod_identity = false."
  }
}

variable "oidc_provider_url" {
  type        = string
  description = "Issuer URL of the cluster OIDC provider, without the https:// prefix. Required only when use_pod_identity = false. Used in the IRSA sub/aud trust conditions."
  default     = null

  validation {
    condition     = var.use_pod_identity || (var.oidc_provider_url != null && length(var.oidc_provider_url) > 0)
    error_message = "oidc_provider_url is required when use_pod_identity = false."
  }
}

variable "chart_version" {
  type        = string
  description = "Version of the aws-load-balancer-controller Helm chart. Keep in sync with the bundled iam_policy.json (both pinned to the same controller release). For EKS 1.32, use '1.12.1' (controller v3.2.2)."
}

variable "service_account_name" {
  type        = string
  description = "Name of the Kubernetes service account the controller uses. Must match the IRSA trust policy subject (when using IRSA) or the service account associated with the Pod Identity (when using Pod Identity)."
  default     = "aws-load-balancer-controller"
}

variable "namespace" {
  type        = string
  description = "Namespace to install the controller into."
  default     = "kube-system"
}

variable "role_name" {
  type        = string
  description = "Name of the IRSA role for the controller. Defaults to '<cluster_name>-aws-load-balancer-controller'. Required only when use_pod_identity = false."
  default     = null

  validation {
    condition     = var.use_pod_identity || (var.role_name != null && length(var.role_name) > 0)
    error_message = "role_name is required when use_pod_identity = false."
  }
}
