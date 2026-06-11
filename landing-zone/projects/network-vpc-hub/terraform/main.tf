module "vpc" {
  source = "./modules/vpc"

  vpc_cidr                = var.vpc_cidr
  secondary_cidrs         = var.secondary_cidrs
  name_prefix             = var.name_prefix
  region                  = var.region
  create_internet_gateway = var.create_internet_gateway
}

module "subnets" {
  source = "./modules/subnets"

  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  availability_zones = local.azs
  tiers              = var.tiers
  name_prefix        = var.name_prefix
}

module "nat" {
  source = "./modules/nat"

  vpc_id             = module.vpc.vpc_id
  availability_zones = var.nat_availability_zones
  name_prefix        = var.name_prefix

  # The public regional NAT requires the VPC's IGW to exist first.
  depends_on = [module.vpc]
}

module "routing" {
  source = "./modules/routing"

  vpc_id                   = module.vpc.vpc_id
  subnets_by_tier          = module.subnets.subnets_by_tier
  igw_id                   = module.vpc.igw_id
  internet_gateway_enabled = var.create_internet_gateway
  regional_nat_gateway_id  = module.nat.regional_nat_gateway_id
  name_prefix              = var.name_prefix
}
