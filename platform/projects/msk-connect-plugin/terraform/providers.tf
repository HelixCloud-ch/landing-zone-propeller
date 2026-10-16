provider "aws" {
  region = var.region

  default_tags {
    tags = merge(var.tags, var.consumer_tags, var.propeller_tags)
  }
}
