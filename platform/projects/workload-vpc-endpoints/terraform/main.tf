# Translates tier names into raw IDs and applies the security group fallback
# (security_groups.tf) before handing off to the module. See the README.
locals {
  endpoints = {
    for k, v in var.endpoints : k => {
      name                = v.name
      type                = v.type
      service             = v.service
      service_name        = v.service_name
      subnet_ids          = v.type == "Interface" ? var.subnet_ids_by_tier[v.subnet_tier] : []
      route_table_ids     = v.type == "Gateway" ? [for t in v.route_table_tiers : var.route_table_ids[t]] : []
      security_group_ids  = v.type == "Interface" && length(v.security_group_ids) == 0 ? [aws_security_group.shared[0].id] : v.security_group_ids
      private_dns_enabled = v.private_dns_enabled
      policy_json         = v.policy_json
    }
  }
}

module "vpc_endpoints" {
  source = "../../../shared/modules/vpc-endpoints"

  vpc_id          = var.vpc_id
  endpoints       = local.endpoints
  organization_id = var.organization_id
}
