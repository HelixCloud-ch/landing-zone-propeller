provider "aws" {
  region = var.region
  default_tags {
    tags = merge(var.consumer_tags, var.tags, var.propeller_tags)
  }
}

# Used by the ct-account module. The CT Account Factory product has a
# Resource Update Constraint that blocks tag updates — passing any tags via
# UpdateProvisionedProduct causes a ValidationException. A separate provider
# with no default_tags ensures tags are never sent to the SC API.
provider "aws" {
  alias  = "notags"
  region = var.region
}
