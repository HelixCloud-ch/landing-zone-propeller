variable "region" {
  type        = string
  description = "AWS region where the EKS cluster is deployed."
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Sourced from the eks-cluster project output."
}

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

variable "base_addons" {
  type = map(object({
    enabled              = optional(bool, false)
    version              = optional(string, null)
    configuration_values = optional(string, null)
  }))
  description = "Map of EKS managed add-ons to install via the generic eks-addon-base module. Intended for add-ons that need only a version pin and at most a simple configuration_values JSON string. Keys must match official EKS add-on names. Add-ons requiring dedicated IRSA roles, Helm charts, or complex orchestration should use their own dedicated project instead."
  default = {
    vpc-cni                = { enabled = false }
    kube-proxy             = { enabled = false }
    eks-pod-identity-agent = { enabled = false }
  }
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
