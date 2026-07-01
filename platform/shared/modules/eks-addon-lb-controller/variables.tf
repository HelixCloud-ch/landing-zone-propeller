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
  description = "Version of the aws-load-balancer-controller Helm chart from the https://aws.github.io/eks-charts repository. Keep in sync with the bundled iam_policy.json (both pinned to the same controller release). The chart version tracks the controller appVersion (e.g. '3.4.0' installs controller v3.4.0). Supports Kubernetes 1.22 and later, including 1.36."
}

variable "chart_repository" {
  type        = string
  description = "Helm repository the chart is pulled from. Defaults to the upstream eks-charts repo. Set to an alternative HTTPS index, an OCI registry (oci://...), or a Helm plugin scheme (s3://, gs://) to source the chart from a mirror. The chart name is always 'aws-load-balancer-controller'."
  default     = "https://aws.github.io/eks-charts"
}

variable "create_service_account" {
  type        = bool
  description = "Whether Helm creates the controller's Kubernetes ServiceAccount. Set to false when the ServiceAccount is managed externally (pre-created, GitOps, or a Pod Identity association that owns it) to avoid an ownership conflict. When false under IRSA, the external ServiceAccount must already carry the eks.amazonaws.com/role-arn annotation for role_arn — this module cannot annotate a ServiceAccount it does not create."
  default     = true
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
