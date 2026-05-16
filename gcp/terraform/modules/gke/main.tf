locals {
  cluster_name = "${var.name}-${var.environment}"
}

#---------------------------------------------------------------
# GKE Private Cluster
#---------------------------------------------------------------

module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "~> 43.0"

  project_id = var.project_id
  name       = local.cluster_name
  region     = var.region
  zones      = var.zones

  kubernetes_version      = var.kubernetes_version
  release_channel         = "UNSPECIFIED"
  network                 = var.network_name
  subnetwork              = var.subnetwork_name
  ip_range_pods           = var.pods_range_name
  ip_range_services       = var.services_range_name
  master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  enable_private_nodes    = var.enable_private_nodes
  enable_private_endpoint = var.enable_private_endpoint
  deletion_protection     = false

  # Built-in features (no separate modules needed)
  http_load_balancing        = true
  horizontal_pod_autoscaling = true
  network_policy             = false
  dns_cache                  = true
  gateway_api_channel        = "CHANNEL_STANDARD"
  identity_namespace         = "enabled"

  # Node pools
  remove_default_node_pool = true
  node_pools               = var.node_pools

  node_pools_labels = {
    all = var.labels
  }

  cluster_resource_labels = var.labels
}

#---------------------------------------------------------------
# IAM Bindings
#---------------------------------------------------------------

# CI/CD service account - cluster admin
resource "google_project_iam_member" "cicd_cluster_admin" {
  count = var.cicd_service_account_email != "" ? 1 : 0

  project = var.project_id
  role    = "roles/container.clusterAdmin"
  member  = "serviceAccount:${var.cicd_service_account_email}"
}
