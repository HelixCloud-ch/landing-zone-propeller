# ── Region ────────────────────────────────────────────────────────────────────

variable "region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed."
}

# ── Pipeline inputs (from workload-vpc outputs) ────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "ID of the workload VPC. Sourced from the workload-vpc project output."
}

variable "subnet_ids_by_tier" {
  type        = map(list(string))
  description = "Map of tier name to ordered subnet ID list, from workload-vpc.subnet_ids_by_tier. Terraform parses the value as HCL when receiving it via -var, so no jsondecode is needed."
}

variable "cluster_subnet_tiers" {
  type        = list(string)
  description = "One or more keys in subnet_ids_by_tier whose subnets are attached to the cluster's vpc_config (control-plane cross-account ENIs). aws_eks_cluster allows a single vpc_config block, so all selected tiers are flattened into one subnet_ids list. Requires subnets spanning at least two AZs."

  validation {
    condition     = length(var.cluster_subnet_tiers) > 0
    error_message = "cluster_subnet_tiers must list at least one tier."
  }
}

variable "fargate_subnet_tier" {
  type        = string
  description = "Key in subnet_ids_by_tier used to place Fargate profiles. Defaults to the first entry of cluster_subnet_tiers when null. Ignored when fargate_profiles is empty."
  default     = null
}

# ── Cluster identity ───────────────────────────────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Supplied per consumer in config.auto.tfvars."
}

variable "eks_version" {
  type        = string
  description = "Pinned Kubernetes minor version for the cluster (e.g. \"1.30\"). Must be updated explicitly; no automatic upgrades."
}

# ── Fargate scheduling ─────────────────────────────────────────────────────────
# Leave empty for a plain EKS cluster (control plane only). Populate to also
# create Fargate profiles and the Fargate pod execution role. Node groups and
# mixed (Fargate + EC2) mode are planned for a later iteration.

variable "fargate_profiles" {
  type = list(object({
    name               = string
    namespace          = string
    labels             = optional(map(string), {})
    subnet_tier        = optional(string)
    pod_execution_role = optional(string)
  }))
  description = "Fargate profiles to create. Each entry maps a profile name to a namespace selector and optional label selectors. Set subnet_tier to place a profile in a specific tier of subnet_ids_by_tier (defaults to fargate_subnet_tier). Set pod_execution_role to a role key so the profile assumes a dedicated pod execution role (e.g. \"test\"/\"prod\" for isolated cross-account ECR pull); profiles sharing a role use the same key, and omitting it uses the shared default role. A role is created for each distinct key referenced. When the list is empty, no Fargate profiles or pod execution roles are created (plain EKS cluster)."
  default     = []
}

# ── Cluster behaviour ──────────────────────────────────────────────────────────

variable "authentication_mode" {
  type        = string
  description = "EKS access-config authentication mode: API (recommended), CONFIG_MAP, or API_AND_CONFIG_MAP."
  default     = "API"
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "Control-plane log types forwarded to CloudWatch. Defaults to all five per AWS best practice."
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
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

variable "api_server_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the private Kubernetes API server endpoint on TCP 443. When non-empty, this project creates a security group with these ingress rules and attaches it to the cluster. Required for a private-only cluster (endpoint_public_access = false) whenever something outside the cluster's own security group must call the API — notably a VPC-attached deploy runner applying eks-addons (helm/kubernetes providers) and operator networks reaching over TGW/VPN. Empty (default) creates no security group."
  default     = []

  validation {
    condition     = alltrue([for c in var.api_server_ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "Every api_server_ingress_cidrs entry must be a valid IPv4 CIDR block."
  }
}

variable "additional_security_group_ids" {
  type        = list(string)
  description = "Externally-managed security group IDs to attach to the cluster's cross-account ENIs, in addition to any group this project creates from api_server_ingress_cidrs. Intended for a future centralized security-group plane that owns SG lifecycle: supply IDs here and leave api_server_ingress_cidrs empty. Empty (default) attaches nothing extra."
  default     = []
}

# ── Access entries ─────────────────────────────────────────────────────────────

variable "additional_admin_arns" {
  type        = list(string)
  description = "IAM principal ARNs to grant AmazonEKSClusterAdmin access via EKS access entries. Use this for VPC-attached deploy runners or other roles that need full cluster access but didn't create the cluster."
  default     = []
}

variable "additional_admin_role_names" {
  type        = list(string)
  description = "IAM role names (in the same account) to grant AmazonEKSClusterAdmin access. Resolved to full ARNs automatically."
  default     = []
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
