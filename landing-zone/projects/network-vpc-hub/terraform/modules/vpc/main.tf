locals {
  # EC2 internal-DNS convention: us-east-1 uses "ec2.internal"; every other
  # region uses "<region>.compute.internal".
  dhcp_domain_name = var.region == "us-east-1" ? "ec2.internal" : "${var.region}.compute.internal"
}

resource "aws_vpc" "this" {
  # checkov:skip=CKV2_AWS_11: VPC flow logs are deferred to a tracked issue (network-vpc-hub: enable VPC flow logs). See the project README.
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# Optional: spoke VPCs without centralized egress do not need an IGW.
resource "aws_internet_gateway" "this" {
  count = var.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Lock down the VPC default security group: omitting ingress/egress strips all
# rules (CKV2_AWS_12), so nothing can use the default SG.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_vpc_dhcp_options" "this" {
  domain_name         = local.dhcp_domain_name
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = {
    Name = "${var.name_prefix}-dhcp"
  }
}

resource "aws_vpc_dhcp_options_association" "this" {
  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.this.id
}
