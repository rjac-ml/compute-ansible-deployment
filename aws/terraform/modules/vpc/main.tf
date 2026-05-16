locals {
  name     = var.name
  vpc_cidr = strcontains(var.vpc_cidr, "/") ? var.vpc_cidr : format("%s/16", var.vpc_cidr)

  # Subnet sizing based on AZ count
  subnet_newbits = var.availability_zones_count <= 2 ? 3 : var.availability_zones_count <= 4 ? 4 : 5

  private_subnets = [for k, v in var.azs : cidrsubnet(local.vpc_cidr, local.subnet_newbits, k)]
  public_subnets  = [for k, v in var.azs : cidrsubnet(local.vpc_cidr, local.subnet_newbits, k + var.availability_zones_count)]

  database_private_subnets = var.enable_database_subnets ? [for k, v in var.azs : cidrsubnet(local.vpc_cidr, local.subnet_newbits, k + (2 * var.availability_zones_count))] : []

  # Secondary CIDR subnets (optional, for workloads needing separate IP ranges)
  secondary_newbits                  = var.availability_zones_count <= 2 ? 1 : var.availability_zones_count <= 4 ? 2 : 3
  secondary_ip_range_private_subnets = length(var.secondary_cidr_blocks) > 0 ? [for k, v in var.azs : cidrsubnet(element(var.secondary_cidr_blocks, 0), local.secondary_newbits, k)] : []
}

#---------------------------------------------------------------
# VPC
#---------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.4"

  name = local.name
  cidr = local.vpc_cidr
  azs  = var.azs

  secondary_cidr_blocks = var.secondary_cidr_blocks

  private_subnets = concat(local.private_subnets, local.secondary_ip_range_private_subnets)

  database_subnets                   = local.database_private_subnets
  create_database_subnet_group       = var.enable_database_subnets
  create_database_subnet_route_table = var.enable_database_subnets

  public_subnets     = local.public_subnets
  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  private_subnet_names = concat(
    [for k, v in var.azs : "${local.name}-private-${v}"],
    [for k, v in var.azs : "${local.name}-private-secondary-${v}"]
  )

  tags = var.tags
}

################################################################################
# VPC Endpoints
################################################################################

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name}-vpc-endpoints-sg"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.4"

  vpc_id = module.vpc.vpc_id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags = {
        Name = "${local.name}-s3-vpc-endpoint"
      }
    }
  }
  tags = var.tags
}
