locals {
  # If OU IDs are provided, scope pull access to those OUs.
  # Otherwise, grant pull access to the entire organization.
  pull_access_org_paths = length(var.pull_access_ou_ids) > 0 ? [
    for ou_id in var.pull_access_ou_ids :
    "${var.organization_id}/*/${ou_id}/*"
  ] : ["${var.organization_id}/*"]
}

module "ecr" {
  source = "../../../shared/modules/ecr"

  repository_creation_templates = var.repository_creation_templates
  default_repository_tags       = merge(var.consumer_tags, var.tags, var.propeller_tags)

  create_registry_policy = var.create_registry_policy && var.organization_id != ""
  pull_access_org_paths  = local.pull_access_org_paths
}
