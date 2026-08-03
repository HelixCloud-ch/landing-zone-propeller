output "endpoint" {
  value = local.endpoint
}

output "secret_name" {
  value = "${var.identifier}-secret"
}
