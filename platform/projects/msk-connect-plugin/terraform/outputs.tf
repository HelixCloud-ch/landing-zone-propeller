output "plugin_arns" {
  description = "Custom plugin ARNs, keyed by \"<flavour>-<version>\"."
  value       = { for k, p in aws_mskconnect_custom_plugin.this : k => p.arn }
}

output "plugin_revisions" {
  description = "Latest custom plugin revision, keyed by \"<flavour>-<version>\", for connectors that pin a revision."
  value       = { for k, p in aws_mskconnect_custom_plugin.this : k => p.latest_revision }
}

output "default_plugin_arns" {
  description = "Custom plugin ARN of the default version, keyed by flavour, for a consumer that wants \"the current one\" rather than naming a version."
  value = {
    for flavour, version in var.default_versions :
    flavour => aws_mskconnect_custom_plugin.this["${flavour}-${version}"].arn
  }
}

output "default_plugin_revisions" {
  description = "Latest custom plugin revision of the default version, keyed by flavour."
  value = {
    for flavour, version in var.default_versions :
    flavour => aws_mskconnect_custom_plugin.this["${flavour}-${version}"].latest_revision
  }
}
