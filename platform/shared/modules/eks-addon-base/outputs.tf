output "addon_version" {
  description = "Resolved version of the installed add-on."
  value       = aws_eks_addon.this.addon_version
}

output "addon_arn" {
  description = "ARN of the add-on."
  value       = aws_eks_addon.this.arn
}

output "latest_compatible_version" {
  description = "Most recent compatible version for the cluster's Kubernetes release. Useful for planning upgrades."
  value       = data.aws_eks_addon_version.this.version
}
