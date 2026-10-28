provider "aws" {
  region = var.region

  default_tags {
    tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
  }
}

# Used by the ct-account module. The CT Account Factory product must not
# receive tags (see README), so this alias carries no default_tags.
provider "aws" {
  alias  = "notags"
  region = var.region
}
