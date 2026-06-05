data "aws_organizations_organization" "current" {}

# Discover the AWSControlTowerBaseline ARN dynamically
data "external" "ct_baseline_arn" {
  program = ["bash", "-c", "cat > /dev/null && aws controltower list-baselines --region ${var.region} --output json | jq '{baseline_arn: (.baselines[] | select(.name == \"AWSControlTowerBaseline\") | .arn)}'"]
}

locals {
  org_root_id  = data.aws_organizations_organization.current.roots[0].id
  baseline_arn = data.external.ct_baseline_arn.result["baseline_arn"]
}
