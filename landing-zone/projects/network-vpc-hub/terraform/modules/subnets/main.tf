locals {
  # Flatten the {enabled tier × AZ} product into a single map keyed by
  # "<tier>-<az_index>". A disabled tier contributes nothing, so its outputs
  # collapse to an empty list. CIDRs come from the tier's explicit cidrs list
  # when set, otherwise they are derived from the VPC CIDR.
  subnet_instances = merge([
    for tier_name, tier in var.tiers : {
      for az_index, az in var.availability_zones :
      "${tier_name}-${az_index}" => {
        tier                    = tier_name
        az                      = az
        az_index                = az_index
        cidr                    = tier.cidrs != null ? tier.cidrs[az_index] : cidrsubnet(var.vpc_cidr, tier.newbits, tier.netnum_base + az_index)
        map_public_ip_on_launch = tier.map_public_ip_on_launch
      }
    } if tier.enabled
  ]...)
}

resource "aws_subnet" "this" {
  # checkov:skip=CKV_AWS_130: The public tier intentionally auto-assigns public IPs (it hosts internet-facing ingress). Non-public tiers set map_public_ip_on_launch = false. This is a single for_each resource, so the skip is declared once.
  for_each = local.subnet_instances

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.map_public_ip_on_launch

  tags = {
    Name = "${var.name_prefix}-${each.value.tier}-${each.value.az}"
  }
}
