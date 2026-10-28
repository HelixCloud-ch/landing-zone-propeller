output "tg_arn" {
  description = "ARN of the ALB target group. Consumed by Kubernetes Ingress action annotations via alb.ingress.kubernetes.io/actions.<name>. Multiple rules can forward to the same target group and differentiate buckets via host-header-rewrite."
  value       = aws_lb_target_group.this.arn
}
