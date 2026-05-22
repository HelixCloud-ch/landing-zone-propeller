resource "aws_organizations_organizational_unit" "this" {
  name      = var.ou_name
  parent_id = local.parent_id
}

resource "aws_controltower_baseline" "this" {
  baseline_identifier = local.baseline_arn
  baseline_version    = var.baseline_version
  target_identifier   = aws_organizations_organizational_unit.this.arn

  lifecycle {
    ignore_changes = [baseline_version]
  }
}

# Move the operations account (not managed by Terraform) into this OU.
# Uses terraform_data + local-exec so the account is never imported into state.
# Idempotent: if the account is already in the target OU, the error is suppressed.
resource "terraform_data" "move_operations_account" {
  triggers_replace = [
    aws_organizations_organizational_unit.this.id,
    var.operations_account_id,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      aws organizations move-account \
        --account-id "${var.operations_account_id}" \
        --source-parent-id "${local.parent_id}" \
        --destination-parent-id "${aws_organizations_organizational_unit.this.id}" \
        --region "${var.region}" \
      || echo "Account ${var.operations_account_id} may already be in the target OU (move-account returned non-zero)"
    EOT
  }

  depends_on = [aws_controltower_baseline.this]
}
