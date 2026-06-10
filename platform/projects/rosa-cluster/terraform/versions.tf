terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.4"
    }
  }

  backend "s3" {}
}
