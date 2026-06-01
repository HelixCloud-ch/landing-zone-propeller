resource "aws_ssm_parameter" "echo" {
  name  = "/example/terraform-echo"
  type  = "String"
  value = "Echo: ${var.upstream_message}"
}
