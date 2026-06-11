provider "aws" {
  region = var.region
  default_tags {
    tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
  }
}

provider "rhcs" {
  client_id     = local.ocm_credentials.client_id
  client_secret = local.ocm_credentials.client_secret
}
