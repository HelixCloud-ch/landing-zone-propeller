# ── Cluster identity ──────────────────────────────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster."
}

variable "eks_version" {
  type        = string
  description = "Pinned Kubernetes minor version for the cluster (e.g. \"1.30\"). Must be updated explicitly; no automatic upgrades."
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "ID of the workload VPC. Sourced from workload-vpc.vpc_id."
}

variable "subnet_ids" {
  type        = list(string)
  description = "App-tier private subnet IDs (one per availability zone) used for Fargate profiles and cluster cross-account ENIs."
}

variable "endpoint_private_access" {
  type        = bool
  description = "Enable private API server endpoint (reachable from within the VPC). Should be true whenever public access is disabled or restricted, so that Fargate/node kubelets can reach the control plane."
  default     = true
}

variable "endpoint_public_access" {
  type        = bool
  description = "Enable public API server endpoint. Set to false for private-only clusters (recommended for production); set to true when operators need to reach the API without a VPN or Direct Connect."
  default     = false
}

# ── Cluster behaviour ─────────────────────────────────────────────────────────

variable "authentication_mode" {
  type        = string
  description = "EKS access-config authentication mode. 'API' (recommended for new clusters — no ConfigMap dependency), 'CONFIG_MAP', or 'API_AND_CONFIG_MAP' (migration path from ConfigMap-based clusters)."
  default     = "API"

  validation {
    condition     = contains(["API", "CONFIG_MAP", "API_AND_CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be one of: API, CONFIG_MAP, API_AND_CONFIG_MAP."
  }
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "Control-plane log types forwarded to CloudWatch. Defaults to all five types per AWS best practice."
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition = alltrue([
      for t in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "Valid log types: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "enable_oidc_provider" {
  type        = bool
  description = <<-EOT
    Create an IAM OIDC identity provider for this cluster, which enables IAM
    Roles for Service Accounts (IRSA).

    **Required when using Fargate.** The EKS Pod Identity Agent runs as a
    DaemonSet on EC2 nodes and is therefore incompatible with Fargate
    (AWS docs: "Pods that run on AWS Fargate aren't supported"). IRSA/OIDC is
    the only supported mechanism for granting AWS IAM permissions to pods
    running on Fargate.

    For EC2-only clusters, IRSA and EKS Pod Identity can coexist on the same
    cluster: set this to true if any workload uses IRSA, leave it false if all
    workloads use Pod Identity exclusively.
  EOT
  default     = true
}


# ── Secrets encryption ─────────────────────────────────────────────────────────

variable "secrets_encryption_enabled" {
  type        = bool
  description = "When true, enables CMK envelope encryption for Kubernetes secrets using kms_key_arn."
  default     = false
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the symmetric CMK used to encrypt Kubernetes secrets. Required when secrets_encryption_enabled is true; ignored otherwise."
  default     = null
}

