variable "region" {
  type        = string
  description = "AWS region to deploy into."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-1)."
  }
}

# ── Cluster ──────────────────────────────────────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA HCP cluster (max 15 characters for domain prefix)."

  validation {
    condition     = length(var.cluster_name) <= 15
    error_message = "Cluster name must be 15 characters or fewer."
  }
}

variable "openshift_version" {
  type        = string
  description = "OpenShift version to deploy (e.g. 4.17.6)."
}

variable "replicas" {
  type        = number
  description = "Number of worker nodes. Must be a multiple of the number of private subnets."
  default     = 3
}

variable "compute_machine_type" {
  type        = string
  description = "EC2 instance type for worker nodes."
  default     = "m5.xlarge"
}

variable "private" {
  type        = bool
  description = "Deploy a private cluster (API and ingress not publicly accessible)."
  default     = true
}

variable "create_admin_user" {
  type        = bool
  description = "Create an htpasswd admin user for initial cluster access. Credentials are stored in Secrets Manager."
  default     = true
}

# ── Billing ──────────────────────────────────────────────────────────────────

variable "aws_billing_account_id" {
  type        = string
  description = "AWS account ID where ROSA billing is linked. Only needed if different from the deployment account (e.g. management account in an Organization)."
  default     = null
}

# ── Network (from VPC project outputs via pipeline) ──────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID (from VPC project output)."
}

variable "machine_cidr" {
  type        = string
  description = "VPC CIDR block — must match the VPC used for subnets."

  validation {
    condition     = can(cidrhost(var.machine_cidr, 0))
    error_message = "machine_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "subnet_ids_json" {
  type        = string
  description = "JSON string of subnet tier map (from VPC project output). Decoded to extract private/public tiers."
}

variable "private_subnet_tier" {
  type        = string
  description = "Key in the subnet map to use for private subnets (worker nodes)."
  default     = "private"
}

variable "public_subnet_tier" {
  type        = string
  description = "Key in the subnet map to use for public subnets (only used if private = false)."
  default     = "public"
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones matching the subnets."
}

# ── Secrets ──────────────────────────────────────────────────────────────────

variable "ocm_secret_name" {
  type        = string
  description = "Name of the Secrets Manager secret containing OCM client_id and client_secret."
  default     = "propeller/rosa/ocm-token"
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Per-project tags applied to all resources via provider default_tags."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Pipeline-wide tags applied to all resources via provider default_tags."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Framework-managed tags applied to all resources via provider default_tags."
  default     = {}
}
