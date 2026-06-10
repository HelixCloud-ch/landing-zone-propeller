# checkov:skip=CKV_AWS_363: auto_accept_shared_attachments disabled — Security Hub EC2.23 (High severity).
resource "aws_ec2_transit_gateway" "this" {
  description = "Landing zone shared Transit Gateway"

  amazon_side_asn                 = var.amazon_side_asn
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "disable"
  dns_support                     = var.dns_support
  vpn_ecmp_support                = var.vpn_ecmp_support

  tags = {
    Name = "${var.name_prefix}-tgw"
  }
}

resource "aws_ram_resource_share" "tgw" {
  name                      = "${var.name_prefix}-tgw-share"
  allow_external_principals = false

  tags = {
    Name = "${var.name_prefix}-tgw-share"
  }
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# Share the TGW with the entire AWS Organization so any vended workload account
# can create a VPC attachment without per-account or per-OU wiring.
# Requires RAM org-sharing to be active (org-trusted-access project).
resource "aws_ram_principal_association" "org" {
  resource_share_arn = aws_ram_resource_share.tgw.arn
  principal          = var.organization_arn
}
