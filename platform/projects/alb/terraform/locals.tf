locals {
  target_group_names = { for k, v in var.ip_target_groups : k => v.name != null ? v.name : "${var.name}-${k}" }

  effective_target_ips = { for k, v in var.ip_target_groups : k => lookup(var.target_ips_by_group, k, v.target_ips) }

  target_group_arns_by_key = merge(
    { for k, m in module.target_group : k => m.arn },
    var.existing_target_group_arns,
  )

  listener_default_actions = {
    for k, l in var.listeners : k => {
      type             = l.default_action.type
      target_group_arn = l.default_action.target_group_key == null ? null : local.target_group_arns_by_key[l.default_action.target_group_key]
      redirect         = l.default_action.redirect
      fixed_response   = l.default_action.fixed_response
    }
  }

  listener_rule_actions = {
    for k, r in var.listener_rules : k => {
      type             = r.action.type
      target_group_arn = r.action.target_group_key == null ? null : local.target_group_arns_by_key[r.action.target_group_key]
      redirect         = r.action.redirect
      fixed_response   = r.action.fixed_response
    }
  }

  listener_ports = distinct([for l in values(var.listeners) : l.port])

  egress_ports = distinct(concat(
    [for tg in values(var.ip_target_groups) : tg.port],
    [for tg in values(var.ip_target_groups) : tonumber(tg.health_check.port) if try(can(regex("^[0-9]{1,5}$", tg.health_check.port)), false)],
    var.security_group_egress_ports,
  ))

  egress_cidrs = !var.create_security_group ? [] : (
    length(var.security_group_egress_cidrs) > 0 ? var.security_group_egress_cidrs : [data.aws_vpc.this[0].cidr_block]
  )

  ingress_rules = var.create_security_group ? {
    for p in setproduct(var.security_group_ingress_cidrs, local.listener_ports) : "${p[0]}|${p[1]}" => { cidr = p[0], port = p[1] }
  } : {}

  egress_rules = {
    for p in setproduct(local.egress_cidrs, local.egress_ports) : "${p[0]}|${p[1]}" => { cidr = p[0], port = p[1] }
  }

  security_group_ids = concat(aws_security_group.this[*].id, var.security_group_ids)
}
