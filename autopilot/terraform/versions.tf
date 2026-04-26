terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.41.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.7.0"
    }
  }

  backend "s3" {}
}
