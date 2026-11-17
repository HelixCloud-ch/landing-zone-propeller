resource "aws_lb_target_group" "this" {
  name                 = var.name
  target_type          = "ip"
  ip_address_type      = "ipv4"
  vpc_id               = var.vpc_id
  port                 = var.port
  protocol             = var.protocol
  protocol_version     = var.protocol_version
  deregistration_delay = var.deregistration_delay == null ? null : tostring(var.deregistration_delay)

  health_check {
    protocol            = coalesce(var.health_check.protocol, var.protocol)
    port                = var.health_check.port
    path                = var.health_check.path
    matcher             = var.health_check.matcher
    interval            = var.health_check.interval
    timeout             = var.health_check.timeout
    healthy_threshold   = var.health_check.healthy_threshold
    unhealthy_threshold = var.health_check.unhealthy_threshold
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_lb_target_group_attachment" "this" {
  for_each          = toset(var.target_ips)
  target_group_arn  = aws_lb_target_group.this.arn
  target_id         = each.value
  availability_zone = var.target_availability_zone
}
