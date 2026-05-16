locals {
  name       = var.name
  region     = var.region
  azs        = slice(data.aws_availability_zones.available.names, 0, var.availability_zones_count)
  partition  = data.aws_partition.current.partition
  account_id = var.account_id
  tags       = var.tags
}


resource "random_bytes" "this" {
  length = 2
}

module "eks" {
  source = "modules/eks"
}
