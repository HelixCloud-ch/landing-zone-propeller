# Query the attachment state via the AWS CLI. The ec2 data source does not
# expose the state attribute, so we shell out for it.
data "external" "attachment_state" {
  program = [
    "bash", "-c",
    <<-BASH
      STATE=$(aws ec2 describe-transit-gateway-vpc-attachments \
        --transit-gateway-attachment-ids "${var.tgw_attachment_id}" \
        --region "${var.region}" \
        --query 'TransitGatewayVpcAttachments[0].State' \
        --output text 2>/dev/null || echo "unknown")
      echo "{\"state\": \"$STATE\"}"
    BASH
  ]
}

# Fail immediately with a clear developer-facing message if the attachment has
# not been accepted yet. The developer should pass the attachment ID to the
# network team; they accept it via network-spokes before re-running this step.
resource "terraform_data" "attachment_ready" {
  input = data.external.attachment_state.result["state"]

  lifecycle {
    precondition {
      condition     = data.external.attachment_state.result["state"] == "available"
      error_message = <<-EOT
        TGW VPC attachment is in state '${data.external.attachment_state.result["state"]}', not 'available'.
        Pass the attachment ID to the network team so they can accept it via network-spokes:
          attachment ID: ${var.tgw_attachment_id}
        They must add it to network-spokes/terraform/config.auto.tfvars (attachment_id, cidrs, segment,
        allowed_destinations) and apply the network-spokes step. Re-run this step once it is available.
      EOT
    }
  }
}

locals {
  # All tiers that have subnets. Keys are tier names; values are ordered subnet
  # objects from workload-vpc. Drives route table creation and associations.
  active_tiers = {
    for tier, ids in var.subnet_ids_by_tier : tier => ids if length(ids) > 0
  }

  # Flat map keyed by "<tier>-<index>" for subnet associations. Plan-stable keys.
  associations = merge([
    for tier, ids in local.active_tiers : {
      for idx, id in ids : "${tier}-${idx}" => {
        subnet_id = id
        tier      = tier
      }
    }
  ]...)

  # Only egress tiers that are actually present.
  egress_tiers_present = [
    for t in var.egress_tiers : t if contains(keys(local.active_tiers), t)
  ]
}

resource "aws_route_table" "this" {
  for_each = local.active_tiers

  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-${each.key}-rt"
  }
}

resource "aws_route_table_association" "this" {
  for_each = local.associations

  subnet_id      = each.value.subnet_id
  route_table_id = aws_route_table.this[each.value.tier].id
}

# 0.0.0.0/0 -> TGW for every egress tier. Single-route resources (no inline
# blocks) so adding further routes later causes no state conflicts.
resource "aws_route" "tgw_default" {
  for_each = toset(local.egress_tiers_present)

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.tgw_id

  depends_on = [terraform_data.attachment_ready]
}
