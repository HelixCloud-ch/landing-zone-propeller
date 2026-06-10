variable "region" {
  type        = string
  description = "AWS region where the Transit Gateway is created (must match the landing zone home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "organization_arn" {
  type        = string
  description = "ARN of the AWS Organization (e.g. 'arn:aws:organizations::123456789012:organization/o-abc123'). Used as the RAM principal to share the TGW with all accounts in the organization. Sourced from bootstrap-parameters."

  validation {
    condition     = can(regex("^arn:aws:organizations::[0-9]{12}:organization/o-[a-z0-9]+$", var.organization_arn))
    error_message = "organization_arn must be a valid AWS Organizations ARN (e.g. arn:aws:organizations::123456789012:organization/o-abc123)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to the TGW and RAM share names (e.g. \"network\" produces \"network-tgw\", \"network-tgw-share\")."
  default     = "network"
}

variable "amazon_side_asn" {
  type        = number
  description = "Private ASN for the Amazon side of BGP sessions. Must be unique among TGWs that may peer in the same region."
  default     = 64512

  validation {
    condition = (
      (var.amazon_side_asn >= 64512 && var.amazon_side_asn <= 65534) ||
      (var.amazon_side_asn >= 4200000000 && var.amazon_side_asn <= 4294967294)
    )
    error_message = "Must be a valid private ASN: 64512-65534 (16-bit) or 4200000000-4294967294 (32-bit)."
  }
}

variable "dns_support" {
  type        = string
  description = "Whether DNS support is enabled on the TGW. Allows VPCs attached to the TGW to resolve public DNS hostnames to private IP addresses across attachments."
  default     = "enable"

  validation {
    condition     = contains(["enable", "disable"], var.dns_support)
    error_message = "Must be \"enable\" or \"disable\"."
  }
}

variable "vpn_ecmp_support" {
  type        = string
  description = "Whether Equal Cost Multipath (ECMP) routing is enabled for VPN attachments. Allows traffic to be distributed across multiple VPN tunnels to the same destination."
  default     = "enable"

  validation {
    condition     = contains(["enable", "disable"], var.vpn_ecmp_support)
    error_message = "Must be \"enable\" or \"disable\"."
  }
}

# ── Tags ──────────────────────────────────────────────────────────────────────

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
