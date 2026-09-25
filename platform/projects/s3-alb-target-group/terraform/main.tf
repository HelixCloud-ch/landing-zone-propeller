locals {
  eni_ids = toset(var.interface_endpoint_eni_ids)
}

# ── ALB target group ──────────────────────────────────────────────────────────
# Backend traffic is HTTPS/443 to the interface endpoint ENIs. Health checks
# probe on HTTP/80 without a bucket-identifying Host header, so S3 answers
# with 307 (redirect to HTTPS) or 405 (method not allowed). Both are accepted
# as healthy responses.
# https://aws.amazon.com/blogs/networking-and-content-delivery/hosting-internal-https-static-websites-with-alb-s3-and-privatelink/

resource "aws_lb_target_group" "this" {
  name        = var.name
  target_type = "ip"
  protocol    = "HTTPS"
  port        = 443
  vpc_id      = var.vpc_id

  health_check {
    protocol            = "HTTP"
    port                = "80"
    path                = "/"
    matcher             = var.health_check_matcher
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
  }
}

# ── Interface endpoint ENI IP attachments ─────────────────────────────────────
# The upstream project publishes ENI IDs as a first-class output. We resolve
# them to their private IPs via a bounded data source and register each as an
# ip-type target.

data "aws_network_interface" "endpoint" {
  for_each = local.eni_ids
  id       = each.value
}

resource "aws_lb_target_group_attachment" "endpoint_eni" {
  for_each         = data.aws_network_interface.endpoint
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = each.value.private_ip
  # availability_zone is omitted: ELB derives the AZ from the private IP when
  # the target lives inside the same VPC as the load balancer.
}
