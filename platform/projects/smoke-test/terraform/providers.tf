provider "aws" {
  region = var.region
  default_tags {
    tags = merge(var.consumer_tags, var.propeller_tags)
  }
}
