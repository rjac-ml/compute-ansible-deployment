locals {
  name            = "${var.name}-${var.environment}"
  subnet_name     = "${local.name}-private"
  pods_range_name = "${local.name}-pods"
  svcs_range_name = "${local.name}-services"
}

#---------------------------------------------------------------
# VPC Network
#---------------------------------------------------------------

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 13.1"

  project_id   = var.project_id
  network_name = local.name

  subnets = [
    {
      subnet_name           = local.subnet_name
      subnet_ip             = var.subnet_ip
      subnet_region         = var.region
      subnet_private_access = true
    }
  ]

  secondary_ranges = {
    (local.subnet_name) = [
      {
        range_name    = local.pods_range_name
        ip_cidr_range = var.pods_range_cidr
      },
      {
        range_name    = local.svcs_range_name
        ip_cidr_range = var.services_range_cidr
      }
    ]
  }
}

#---------------------------------------------------------------
# Cloud Router + Cloud NAT
#---------------------------------------------------------------

module "cloud_router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "~> 8.3"

  count = var.enable_cloud_nat ? 1 : 0

  project_id = var.project_id
  name       = "${local.name}-router"
  network    = module.vpc.network_name
  region     = var.region

  nats = [
    {
      name                               = "${local.name}-nat"
      nat_ip_allocate_option             = "AUTO_ONLY"
      source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
    }
  ]
}
