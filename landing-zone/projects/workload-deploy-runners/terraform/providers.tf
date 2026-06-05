provider "aws" {
  region = var.region
  default_tags {
    tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
  }
}

provider "aws" {
  alias  = "notags"
  region = var.region
}
