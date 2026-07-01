# ── Region ────────────────────────────────────────────────────────────────────

variable "region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed."
}

# ── Pipeline inputs (from the eks-cluster and workload-vpc outputs) ───────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Sourced from the eks-cluster project output."
}

variable "cluster_endpoint" {
  type        = string
  description = "HTTPS endpoint of the EKS API server. Sourced from the eks-cluster project output. Used to configure the kubernetes and helm providers."
}

variable "cluster_certificate_authority_data" {
  type        = string
  description = "Base64-encoded certificate authority data for the EKS cluster. Sourced from the eks-cluster project output. Used to configure the kubernetes and helm providers."
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the IAM OIDC identity provider associated with the EKS cluster. Sourced from the eks-cluster project output. Used as the IRSA trust principal for the LB Controller role. Required only when install_lb_controller = true and lbc_use_pod_identity = false."
  default     = null
}

variable "oidc_provider_url" {
  type        = string
  description = "Issuer URL of the OIDC provider (without the https:// prefix). Sourced from the eks-cluster project output. Used in the IRSA sub condition. Required only when install_lb_controller = true and lbc_use_pod_identity = false."
  default     = null
}

variable "vpc_id" {
  type        = string
  description = "ID of the workload VPC. Sourced from the workload-vpc project output. Passed to the LB Controller Helm release as vpcId. Required only when install_lb_controller = true."
  default     = null
}

# ── CoreDNS managed add-on ─────────────────────────────────────────────────────

variable "install_coredns" {
  type        = bool
  description = "Whether to manage the CoreDNS EKS add-on here. Must be true on pure-Fargate clusters (the default self-managed CoreDNS cannot schedule without nodes). On EC2 node-group clusters EKS provides a working CoreDNS by default, so enable this only to pin or upgrade the add-on version deliberately."
  default     = true
}

variable "coredns_version" {
  type        = string
  description = "Pinned version of the CoreDNS managed EKS add-on (e.g. \"v1.11.4-eksbuild.40\"). Bump in lockstep with the cluster Kubernetes version per the EKS upgrade runbook. Null lets EKS pick the default for the cluster's Kubernetes release. Ignored when install_coredns is false."
  default     = null
}

variable "coredns_compute_type" {
  type        = string
  description = "Compute type CoreDNS pods are scheduled on. Set to \"Fargate\" for pure-Fargate clusters (requires a kube-system Fargate profile on the cluster). Leave null for EC2-based clusters to use the EKS default."
  default     = null

  validation {
    condition     = var.coredns_compute_type == null || contains(["Fargate"], var.coredns_compute_type)
    error_message = "coredns_compute_type must be null or \"Fargate\"."
  }
}

# ── AWS Load Balancer Controller (optional) ────────────────────────────────────

variable "install_lb_controller" {
  type        = bool
  description = "Whether to install the AWS Load Balancer Controller. Set to false for clusters that only need internal DNS and do not require Ingress or Service type=LoadBalancer."
  default     = false
}

variable "lbc_chart_version" {
  type        = string
  description = "Pinned version of the AWS Load Balancer Controller Helm chart from the https://aws.github.io/eks-charts repository. The chart version tracks the controller appVersion (e.g. \"3.4.0\" installs controller v3.4.0). Required only when install_lb_controller = true."
  default     = null
}

variable "lbc_chart_repository" {
  type        = string
  description = "Helm repository the LB Controller chart is pulled from. Defaults to the upstream eks-charts repo. Set to an alternative HTTPS index, an OCI registry (oci://...), or a Helm plugin scheme (s3://, gs://) to source the chart from a mirror."
  default     = "https://aws.github.io/eks-charts"
}

variable "lbc_create_service_account" {
  type        = bool
  description = "Whether Helm creates the LB Controller's Kubernetes ServiceAccount. Set to false when the ServiceAccount is managed externally (pre-created, GitOps, or a Pod Identity association). When false under IRSA, the external ServiceAccount must already carry the eks.amazonaws.com/role-arn annotation."
  default     = true
}

variable "lbc_use_pod_identity" {
  type        = bool
  description = "Whether to use EKS Pod Identity for the Load Balancer Controller. Set to true if the Pod Identity Agent add-on is installed. Not supported on pure-Fargate clusters. Default: false (uses IRSA/OIDC)."
  default     = false
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
