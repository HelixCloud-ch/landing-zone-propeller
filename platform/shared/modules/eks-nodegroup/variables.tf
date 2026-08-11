# ── Cluster reference ──────────────────────────────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster this node group belongs to."

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

# ── Node group identity ───────────────────────────────────────────────────────

variable "node_group_name" {
  type        = string
  description = "Name of the managed node group. Defaults to '<cluster_name>-nodes' if null."
  default     = null
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs where worker nodes are launched (private subnets, spanning at least two AZs for high availability)."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least two subnets (in different AZs) are required for a managed node group."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[a-f0-9]+$", s))])
    error_message = "Each subnet_ids entry must be a valid subnet ID (subnet-...)."
  }
}

# ── Compute ───────────────────────────────────────────────────────────────────

variable "instance_types" {
  type        = list(string)
  description = "Ordered list of EC2 instance types for the node group. EKS selects the first type with available capacity. The AWS default is t3.medium. Validated at plan time via data source (fails if a type is not available in this region)."
  default     = ["t3.medium"]

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "instance_types must contain at least one instance type."
  }
}

variable "capacity_type" {
  type        = string
  description = "Capacity type: ON_DEMAND, SPOT, or CAPACITY_BLOCK."
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT", "CAPACITY_BLOCK"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND, SPOT, or CAPACITY_BLOCK."
  }
}

variable "ami_type" {
  type        = string
  description = "AMI type for the node group. AL2023_x86_64_STANDARD is the current default for EKS-optimized Amazon Linux 2023."
  default     = "AL2023_x86_64_STANDARD"

  validation {
    condition = contains([
      "AL2_x86_64",
      "AL2_x86_64_GPU",
      "AL2_ARM_64",
      "CUSTOM",
      "BOTTLEROCKET_ARM_64",
      "BOTTLEROCKET_x86_64",
      "BOTTLEROCKET_ARM_64_FIPS",
      "BOTTLEROCKET_x86_64_FIPS",
      "BOTTLEROCKET_ARM_64_NVIDIA",
      "BOTTLEROCKET_x86_64_NVIDIA",
      "BOTTLEROCKET_ARM_64_NVIDIA_FIPS",
      "BOTTLEROCKET_x86_64_NVIDIA_FIPS",
      "WINDOWS_CORE_2019_x86_64",
      "WINDOWS_FULL_2019_x86_64",
      "WINDOWS_CORE_2022_x86_64",
      "WINDOWS_FULL_2022_x86_64",
      "WINDOWS_CORE_2025_x86_64",
      "WINDOWS_FULL_2025_x86_64",
      "AL2023_x86_64_STANDARD",
      "AL2023_ARM_64_STANDARD",
      "AL2023_x86_64_NEURON",
      "AL2023_x86_64_NVIDIA",
      "AL2023_ARM_64_NVIDIA",
    ], var.ami_type)
    error_message = "ami_type must be a valid EKS node group AMI type (see https://docs.aws.amazon.com/eks/latest/APIReference/API_Nodegroup.html)."
  }
}

variable "release_version" {
  type        = string
  description = "AMI release version for the node group (e.g. '1.30.0-20240625'). When null, EKS uses the latest recommended version for the cluster's Kubernetes version."
  default     = null
}

variable "disk_size" {
  type        = number
  description = "Root EBS volume size in GiB. When null, EKS uses its default (20 GiB Linux, 50 GiB Windows). Ignored when a launch template is provided."
  default     = null

  validation {
    condition     = var.disk_size == null || (var.disk_size >= 1 && var.disk_size <= 16384)
    error_message = "disk_size must be null or between 1 and 16384 GiB."
  }
}

# ── Scaling ───────────────────────────────────────────────────────────────────

variable "desired_size" {
  type        = number
  description = "Desired number of worker nodes. Ignored after initial creation when the autoscaler manages scaling."
  default     = 2

  validation {
    condition     = var.desired_size >= 0
    error_message = "desired_size must be >= 0."
  }

  validation {
    condition     = var.desired_size >= var.min_size
    error_message = "desired_size must be >= min_size."
  }

  validation {
    condition     = var.desired_size <= var.max_size
    error_message = "desired_size must be <= max_size."
  }
}

variable "min_size" {
  type        = number
  description = "Minimum number of worker nodes."
  default     = 1

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be >= 0."
  }
}

variable "max_size" {
  type        = number
  description = "Maximum number of worker nodes."
  default     = 10

  validation {
    condition     = var.max_size >= 1
    error_message = "max_size must be >= 1."
  }

  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be >= min_size."
  }
}

variable "max_unavailable" {
  type        = number
  description = "Maximum number of nodes unavailable during a rolling update."
  default     = 1

  validation {
    condition     = var.max_unavailable >= 1
    error_message = "max_unavailable must be >= 1."
  }
}

# ── Launch template ───────────────────────────────────────────────────────────

variable "launch_template_id" {
  type        = string
  description = "ID of an externally-managed launch template. When null (default), no launch template is used and EKS applies its own defaults (AL2023 AMI, IMDSv2, gp3 root volume)."
  default     = null
}

variable "launch_template_version" {
  type        = string
  description = "Version of the launch template to use. Only relevant when launch_template_id is set. Defaults to '$Latest'."
  default     = "$Latest"
}

# ── IAM ───────────────────────────────────────────────────────────────────────

variable "create_node_role" {
  type        = bool
  description = "Create the node IAM role. Set false to supply an externally-managed role via node_role_arn."
  default     = true
}

variable "node_role_arn" {
  type        = string
  description = "ARN of an externally-managed node IAM role. Required when create_node_role is false; ignored otherwise."
  default     = null

  validation {
    condition     = var.create_node_role || (var.node_role_arn != null && length(var.node_role_arn) > 0)
    error_message = "node_role_arn is required when create_node_role is false."
  }
}

variable "additional_node_policy_arns" {
  type        = list(string)
  description = "Additional IAM policy ARNs to attach to the node role (e.g. cross-account ECR pull, custom application policies). Only used when create_node_role is true."
  default     = []

  validation {
    condition     = alltrue([for arn in var.additional_node_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "Each additional_node_policy_arns entry must be a valid IAM policy ARN (arn:aws:iam::...)."
  }
}

variable "default_node_policy_arns" {
  type        = list(string)
  description = <<-EOT
    Managed policy ARNs attached to the node role by default (in addition to the
    always-attached AmazonEKSWorkerNodePolicy). The default set enables nodes to
    boot, pull images, and be reachable via SSM. Override to an empty list if you
    prefer delegating these policies to addon projects (eks-addons for VPC CNI,
    eks-ecr-pull for ECR, etc.) — but note that nodes need ECR read and CNI
    permissions at boot time before any addon project runs.
  EOT
  default = [
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]

  validation {
    condition     = alltrue([for arn in var.default_node_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "Each default_node_policy_arns entry must be a valid IAM policy ARN (arn:aws:iam::...)."
  }
}

# ── Labels and taints ─────────────────────────────────────────────────────────

variable "labels" {
  type        = map(string)
  description = "Kubernetes labels applied to all nodes in this group."
  default     = {}
}

variable "taints" {
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  description = "Kubernetes taints applied to all nodes in this group. Effect must be NO_SCHEDULE, NO_EXECUTE, or PREFER_NO_SCHEDULE."
  default     = []

  validation {
    condition = alltrue([
      for t in var.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)
    ])
    error_message = "Taint effect must be NO_SCHEDULE, NO_EXECUTE, or PREFER_NO_SCHEDULE."
  }
}
