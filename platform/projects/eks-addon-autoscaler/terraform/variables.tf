variable "region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed."
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Sourced from the eks-cluster project output."
}

variable "cluster_endpoint" {
  type        = string
  description = "HTTPS endpoint of the EKS API server. Sourced from the eks-cluster project output. Used to configure the helm provider."
}

variable "cluster_certificate_authority_data" {
  type        = string
  description = "Base64-encoded certificate authority data for the EKS cluster. Sourced from the eks-cluster project output. Used to configure the helm provider."
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the IAM OIDC provider for the cluster. Sourced from the eks-cluster project output."
}

variable "oidc_provider_url" {
  type        = string
  description = "Issuer URL of the OIDC provider (without the https:// prefix). Sourced from the eks-cluster project output."
}

variable "chart_version" {
  type        = string
  description = "Version of the cluster-autoscaler Helm chart (e.g. '9.57.0'). Pin to match the EKS Kubernetes version per the CA compatibility matrix."
}

variable "chart_repository" {
  type        = string
  description = "Helm repository for the cluster-autoscaler chart. Override to a mirror in air-gapped environments."
  default     = "https://kubernetes.github.io/autoscaler"
}

variable "image_repository" {
  type        = string
  description = "Container image repository for the autoscaler. Override to an ECR mirror in air-gapped environments. Null uses the chart default."
  default     = null
}

variable "image_tag" {
  type        = string
  description = "Container image tag for the autoscaler. Null uses the chart's appVersion."
  default     = null
}

variable "role_name" {
  type        = string
  description = "Name of the IRSA role for the autoscaler. Defaults to '<cluster_name>-cluster-autoscaler'."
  default     = null
}

variable "service_account_name" {
  type        = string
  description = "Name of the Kubernetes service account the autoscaler uses."
  default     = "cluster-autoscaler"
}

variable "namespace" {
  type        = string
  description = "Namespace to deploy the autoscaler into."
  default     = "kube-system"
}

variable "create_service_account" {
  type        = bool
  description = "Whether Helm creates the Kubernetes ServiceAccount for the autoscaler. Set to false when the ServiceAccount is managed externally (GitOps, another Terraform step, or a Pod Identity association). When false, the existing ServiceAccount must already carry the eks.amazonaws.com/role-arn annotation."
  default     = true
}

variable "use_pod_identity" {
  type        = bool
  description = "Whether to use EKS Pod Identity instead of IRSA/OIDC. When true, no IRSA role is created and no role-arn annotation is set on the ServiceAccount. The Pod Identity association must be created separately (e.g. via aws_eks_pod_identity_association)."
  default     = false
}

variable "existing_role_arn" {
  type        = string
  description = "ARN of a pre-existing IAM role to use instead of creating one. When set, no role or policy resources are created — the provided role is annotated on the ServiceAccount directly. Useful when the role is managed outside this project or shared across clusters."
  default     = null
}

variable "extra_set" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Additional Helm set values passed to the release."
  default     = []
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
