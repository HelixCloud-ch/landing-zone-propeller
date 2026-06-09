locals {
  # Build org paths from organization_id + OU IDs for cross-account pull access.
  # If OU IDs are provided, scope to those OUs. Otherwise, share whole org.
  pull_access_org_paths = var.organization_id != "" ? (
    length(var.pull_access_ou_ids) > 0 ? [
      for ou_id in var.pull_access_ou_ids :
      "${var.organization_id}/*/${ou_id}/*"
    ] : ["${var.organization_id}/*"]
  ) : []
}

module "ecr" {
  source = "../../../shared/modules/ecr"

  repository_creation_templates = var.repository_creation_templates
  default_repository_tags       = merge(var.consumer_tags, var.tags, var.propeller_tags)
  pull_access_org_paths         = local.pull_access_org_paths
}
