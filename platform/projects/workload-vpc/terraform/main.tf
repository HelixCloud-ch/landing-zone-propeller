module "vpc" {
  source = "./modules/vpc"

  vpc_cidr    = var.vpc_cidr
  name_prefix = var.name_prefix
  region      = var.region
}

module "subnets" {
  source = "./modules/subnets"

  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  availability_zones = local.azs
  tiers              = var.tiers
  name_prefix        = var.name_prefix
}

module "tgw_attach" {
  source = "./modules/tgw-attach"

  vpc_id      = module.vpc.vpc_id
  tgw_id      = var.tgw_id
  subnet_ids  = [for s in module.subnets.subnets_by_tier["tgw-attach"] : s.id]
  name_prefix = var.name_prefix
}
