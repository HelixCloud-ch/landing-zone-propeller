# Validate that each requested instance type is available in the current region.
# Fails at plan time via the instance_types variable validation block (Terraform >= 1.9).
# Uses a single query with all requested types — returned list only contains those
# that exist in the region, so a length mismatch signals an invalid type.
data "aws_ec2_instance_type_offerings" "validate" {
  filter {
    name   = "instance-type"
    values = var.instance_types
  }

  location_type = "region"
}
