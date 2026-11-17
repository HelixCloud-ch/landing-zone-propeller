data "aws_vpc" "this" {
  count = var.create_security_group && length(var.security_group_egress_cidrs) == 0 ? 1 : 0
  id    = var.vpc_id
}

resource "aws_security_group" "this" {
  count       = var.create_security_group ? 1 : 0
  name        = "${var.name}-alb"
  description = "Application load balancer ${var.name}"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each          = local.ingress_rules
  security_group_id = aws_security_group.this[0].id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  description       = "Clients to listener port ${each.value.port}"
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each          = local.egress_rules
  security_group_id = aws_security_group.this[0].id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  description       = "Targets and health checks on port ${each.value.port}"
}

module "alb" {
  source                     = "../../../shared/modules/alb"
  name                       = var.name
  internal                   = var.internal
  subnet_ids                 = var.subnet_ids
  security_group_ids         = local.security_group_ids
  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection
  desync_mitigation_mode     = var.desync_mitigation_mode
  access_logs                = var.access_logs
  connection_logs            = var.connection_logs
  web_acl_arn                = var.web_acl_arn
}

module "target_group" {
  source                   = "../../../shared/modules/alb-ipv4-target-group"
  for_each                 = var.ip_target_groups
  name                     = local.target_group_names[each.key]
  vpc_id                   = var.vpc_id
  port                     = each.value.port
  protocol                 = each.value.protocol
  protocol_version         = each.value.protocol_version
  deregistration_delay     = each.value.deregistration_delay
  health_check             = each.value.health_check
  target_ips               = local.effective_target_ips[each.key]
  target_availability_zone = each.value.target_availability_zone
}

module "listener" {
  source            = "../../../shared/modules/alb-listener"
  for_each          = var.listeners
  load_balancer_arn = module.alb.arn
  port              = each.value.port
  protocol          = each.value.protocol
  certificate_arns  = [for c in each.value.certificate_keys : var.certificate_arns[c]]
  ssl_policy        = each.value.ssl_policy
  allow_plain_http  = each.value.allow_plain_http
  default_action    = local.listener_default_actions[each.key]
}

module "listener_rule" {
  source       = "../../../shared/modules/alb-listener-rule"
  for_each     = var.listener_rules
  listener_arn = module.listener[each.value.listener_key].arn
  priority     = each.value.priority
  name         = coalesce(each.value.name, each.key)
  conditions   = each.value.conditions
  action       = local.listener_rule_actions[each.key]
}
