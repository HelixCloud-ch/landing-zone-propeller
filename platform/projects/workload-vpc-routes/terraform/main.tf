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

# Look up the route tables that workload-vpc created, one per egress tier.
# We find them via subnet ID (each tier's first subnet) rather than re-creating them.
data "aws_route_table" "egress" {
  for_each = toset(var.egress_tiers)

  subnet_id = var.subnet_ids_by_tier[each.key][0]
}

# 0.0.0.0/0 -> TGW for every egress tier. Single-route resources so adding
# further routes later causes no state conflicts.
resource "aws_route" "tgw_default" {
  for_each = toset(var.egress_tiers)

  route_table_id         = data.aws_route_table.egress[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.tgw_id

  depends_on = [terraform_data.attachment_ready]
}
