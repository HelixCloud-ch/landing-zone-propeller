output "arn" {
  description = "Listener ARN."
  value       = aws_lb_listener.this.arn
}

output "port" {
  description = "Listener port."
  value       = aws_lb_listener.this.port
}

output "protocol" {
  description = "Listener protocol."
  value       = aws_lb_listener.this.protocol
}
