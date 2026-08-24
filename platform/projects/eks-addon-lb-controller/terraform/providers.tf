provider "aws" {
  region = var.region
  default_tags {
    tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
  }
}

# When chart_repository is a private ECR OCI registry, the Helm provider needs
# registry credentials to fetch the chart. Derive the registry host and pull a
# short-lived ECR token. This works cross-account: the token authenticates the
# caller identity and the target repository's policy authorizes the pull.
locals {
  chart_repo_is_oci = startswith(var.chart_repository, "oci://")
  chart_registry    = local.chart_repo_is_oci ? "oci://${split("/", trimprefix(var.chart_repository, "oci://"))[0]}" : null
}

data "aws_ecr_authorization_token" "chart" {
  count = local.chart_repo_is_oci ? 1 : 0
}

provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }

  registries = local.chart_repo_is_oci ? [{
    url      = local.chart_registry
    username = data.aws_ecr_authorization_token.chart[0].user_name
    password = data.aws_ecr_authorization_token.chart[0].password
  }] : []
}
