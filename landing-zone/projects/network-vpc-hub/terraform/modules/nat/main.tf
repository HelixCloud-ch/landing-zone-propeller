locals {
  manual_mode = length(var.availability_zones) > 0
}

# One Elastic IP per pinned AZ (manual mode only). Auto mode lets AWS manage
# EIP allocation, so none are created.
resource "aws_eip" "this" {
  for_each = toset(var.availability_zones)

  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-${each.value}"
  }
}

# Regional NAT gateway: operates at VPC level and auto-expands across AZs.
# No public subnet or per-AZ NAT gateway is required.
#
# - Auto mode (availability_zones empty): omit availability_zone_address, AWS
#   manages AZ coverage and EIPs.
# - Manual mode (availability_zones set): one availability_zone_address block
#   per pinned AZ, each with its own EIP. Pinning fewer AZs reduces cost.
resource "aws_nat_gateway" "this" {
  vpc_id            = var.vpc_id
  availability_mode = "regional"
  connectivity_type = "public"

  dynamic "availability_zone_address" {
    for_each = local.manual_mode ? var.availability_zones : []
    content {
      allocation_ids    = [aws_eip.this[availability_zone_address.value].id]
      availability_zone = availability_zone_address.value
    }
  }

  tags = {
    Name = "${var.name_prefix}-nat"
  }
}
