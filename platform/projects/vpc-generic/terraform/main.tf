module "vpc" {
  source = "../../../shared/modules/vpc"

  vpc_cidr    = var.vpc_cidr
  name_prefix = var.name_prefix
  region      = var.region
}

module "subnets" {
  source = "../../../shared/modules/vpc-subnets"

  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  availability_zones = local.azs
  tiers              = var.tiers
  name_prefix        = var.name_prefix
}
