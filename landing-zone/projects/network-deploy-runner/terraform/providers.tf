# Runs in the management account and assumes AWSControlTowerExecution in the
# Network account. The Network account has no deploy-runner yet — that is
# exactly what this project provisions.
provider "aws" {
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.network_account_id}:role/${var.assume_role_name}"
  }

  default_tags {
    tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
  }
}
