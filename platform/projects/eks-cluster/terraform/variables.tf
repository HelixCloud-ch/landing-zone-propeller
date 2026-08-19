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
  description = "Map of tier name to ordered subnet ID list, from workload-vpc.subnet_ids_by_tier. See README ('Pipeline inputs')."
}

variable "cluster_subnet_tiers" {
  type        = list(string)
  description = "Keys in subnet_ids_by_tier attached to the cluster's vpc_config. Requires at least two AZs. See README ('Pipeline inputs')."

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
# create Fargate profiles and the Fargate pod execution role.

variable "fargate_profiles" {
  type = list(object({
    name               = string
    namespace          = string
    labels             = optional(map(string), {})
    subnet_tier        = optional(string)
    pod_execution_role = optional(string)
  }))
  description = "Fargate profiles to create. Empty (default) creates none. See README ('Fargate profiles') for the pod_execution_role sharing model."
  default     = []
}

# ── EC2 node groups ───────────────────────────────────────────────────────────
# Leave empty for a Fargate-only or control-plane-only cluster. Populate to
# create managed node groups (EC2-backed). Can coexist with fargate_profiles
# for mixed-mode clusters.

variable "node_groups" {
  type = list(object({
    name            = string
    subnet_tier     = optional(string)
    instance_types  = optional(list(string), ["t3.medium"])
    capacity_type   = optional(string, "ON_DEMAND")
    ami_type        = optional(string, "AL2023_x86_64_STANDARD")
    release_version = optional(string)
    disk_size       = optional(number)
    desired_size    = optional(number, 2)
    min_size        = optional(number, 1)
    max_size        = optional(number, 10)
    max_unavailable = optional(number, 1)
    labels          = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    node_role_arn           = optional(string)
    launch_template_id      = optional(string)
    launch_template_version = optional(string, "$Latest")
  }))
  description = "Managed node groups to create. Each shares the default node role unless node_role_arn is set. Empty (default) creates none."
  default     = []
}

variable "node_role_policy_arns" {
  type        = list(string)
  description = "IAM policy ARNs on the shared node role. Replaces the whole set, does not append. See README ('Node IAM role')."
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]
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
  description = "CIDR blocks allowed to reach the private API server on TCP 443. Empty (default) creates no security group. See README ('API server access')."
  default     = []

  validation {
    condition     = alltrue([for c in var.api_server_ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "Every api_server_ingress_cidrs entry must be a valid IPv4 CIDR block."
  }
}

variable "additional_security_group_ids" {
  type        = list(string)
  description = "Externally-managed security group IDs attached to the cluster's cross-account ENIs. See README ('API server access')."
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
