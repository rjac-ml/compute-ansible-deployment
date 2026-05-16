output "network_name" {
  description = "The name of the VPC network"
  value       = module.vpc.network_name
}

output "network_self_link" {
  description = "The self link of the VPC network"
  value       = module.vpc.network_self_link
}

output "subnetwork_name" {
  description = "The name of the private subnet"
  value       = module.vpc.subnets["${var.region}/${local.subnet_name}"].name
}

output "subnetwork_self_link" {
  description = "The self link of the private subnet"
  value       = module.vpc.subnets["${var.region}/${local.subnet_name}"].self_link
}

output "pods_range_name" {
  description = "Name of the secondary IP range for pods"
  value       = local.pods_range_name
}

output "services_range_name" {
  description = "Name of the secondary IP range for services"
  value       = local.svcs_range_name
}
