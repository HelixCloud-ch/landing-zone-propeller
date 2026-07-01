output "addon_version" {
  description = "Resolved version of the installed CoreDNS add-on."
  value       = aws_eks_addon.this.addon_version
}

output "addon_arn" {
  description = "ARN of the CoreDNS add-on."
  value       = aws_eks_addon.this.arn
}
