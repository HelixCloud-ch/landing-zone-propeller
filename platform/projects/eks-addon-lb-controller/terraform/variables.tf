# ── Region ────────────────────────────────────────────────────────────────────

variable "region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed."
}

# ── Pipeline inputs (from eks-cluster and workload-vpc outputs) ───────────────

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
  description = "ARN of the IAM OIDC identity provider associated with the EKS cluster. Sourced from the eks-cluster project output. Used as the IRSA trust principal. Required when use_pod_identity = false."
  default     = null
}

variable "oidc_provider_url" {
  type        = string
  description = "Issuer URL of the OIDC provider (without the https:// prefix). Sourced from the eks-cluster project output. Used in the IRSA sub condition. Required when use_pod_identity = false."
  default     = null
}

variable "vpc_id" {
  type        = string
  description = "ID of the workload VPC. Sourced from the workload-vpc project output. Passed to the LB Controller Helm release as vpcId."
}

# ── LB Controller configuration ───────────────────────────────────────────────

variable "chart_version" {
  type        = string
  description = "Pinned version of the AWS Load Balancer Controller Helm chart from the https://aws.github.io/eks-charts repository. The chart version tracks the controller appVersion (e.g. '3.4.0' installs controller v3.4.0)."
}

variable "chart_repository" {
  type        = string
  description = "Helm repository the LB Controller chart is pulled from. Defaults to the upstream eks-charts repo. Set to an alternative HTTPS index, an OCI registry (oci://...), or a Helm plugin scheme (s3://, gs://) to source the chart from a mirror."
  default     = "https://aws.github.io/eks-charts"
}

variable "role_name" {
  type        = string
  description = "Name of the IRSA role created for the LB Controller. Defaults to '<cluster_name>-aws-load-balancer-controller'. Override only when the naming convention conflicts with an existing role or IAM path constraint."
  default     = null
}

variable "create_service_account" {
  type        = bool
  description = "Whether Helm creates the LB Controller's Kubernetes ServiceAccount. Set to false when the ServiceAccount is managed externally (pre-created, GitOps, or a Pod Identity association). When false under IRSA, the external ServiceAccount must already carry the eks.amazonaws.com/role-arn annotation."
  default     = true
}

variable "use_pod_identity" {
  type        = bool
  description = "Whether to use EKS Pod Identity for the Load Balancer Controller. Set to true if the Pod Identity Agent add-on is installed. Not supported on pure-Fargate clusters. Default: false (uses IRSA/OIDC)."
  default     = false
}

variable "service_account_name" {
  type        = string
  description = "Name of the Kubernetes service account the controller uses. Must match the IRSA trust policy subject or the Pod Identity association."
  default     = "aws-load-balancer-controller"
}

variable "namespace" {
  type        = string
  description = "Namespace to install the controller into."
  default     = "kube-system"
}

variable "iam_policy_json" {
  type        = string
  description = "JSON string of the IAM policy to attach to the controller role. When null (the default), the bundled iam_policy.json matching the default chart_version is used. Override to supply a policy matching a different controller version or to restrict permissions further."
  default     = null
}

# ── Tagging ────────────────────────────────────────────────────────────────────

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
