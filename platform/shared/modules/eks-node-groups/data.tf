# Validate that all requested instance types are available in the current region.
data "aws_ec2_instance_type_offerings" "validate" {
  for_each = toset(flatten([for ng in var.node_groups : ng.instance_types]))

  filter {
    name   = "instance-type"
    values = [each.value]
  }

  location_type = "region"
}
