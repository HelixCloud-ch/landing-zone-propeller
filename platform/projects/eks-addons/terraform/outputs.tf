output "coredns_addon_version" {
  description = "Resolved version of the installed CoreDNS managed add-on. Null when install_coredns = false."
  value       = one(module.coredns[*].addon_version)
}

output "coredns_addon_arn" {
  description = "ARN of the CoreDNS managed add-on. Null when install_coredns = false."
  value       = one(module.coredns[*].addon_arn)
}

output "base_addon_versions" {
  description = "Map of installed base add-on names to their resolved versions. Only includes enabled add-ons."
  value       = { for k, v in module.base_addon : k => v.addon_version }
}
