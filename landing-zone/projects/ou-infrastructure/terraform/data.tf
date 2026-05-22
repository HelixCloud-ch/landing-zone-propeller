data "aws_organizations_organization" "this" {}

# --- Baseline discovery (no TF data source exists for CT baselines) ---

# Discover the AWSControlTowerBaseline definition ARN.
data "external" "ct_baseline_arn" {
  program = ["bash", "-c", "cat > /dev/null && aws controltower list-baselines --region ${var.region} --output json | jq '{baseline_arn: (.baselines[] | select(.name == \"AWSControlTowerBaseline\") | .arn)}'"]
}

locals {
  parent_id    = data.aws_organizations_organization.this.roots[0].id
  baseline_arn = data.external.ct_baseline_arn.result["baseline_arn"]
}
