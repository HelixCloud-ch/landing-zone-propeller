output "smoke_test" {
  description = "Placeholder output to verify Terraform runs correctly."
  value       = "source-bucket terraform works — bucket_name=${var.bucket_name}, region=${var.region}"
}
