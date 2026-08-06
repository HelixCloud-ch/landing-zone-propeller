# Provider is only needed to satisfy the backend and consume tags variables.
# All AWS API calls happen inside the local-exec script (assumed session).
provider "aws" {
  region = var.region
  default_tags {
    tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
  }
}
