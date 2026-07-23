resource "aws_ssm_parameter" "test" {
  name  = "/propeller-smoke/${var.namespace}/${var.project_name}"
  type  = "String"
  value = "deployed by propeller at ${timestamp()}"

  tags = merge(var.consumer_tags, var.propeller_tags)

  lifecycle {
    ignore_changes = [value]
  }
}
