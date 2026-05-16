#---------------------------------------------------------------
# Data Sources for Authentication
#---------------------------------------------------------------

data "google_client_config" "default" {}

#---------------------------------------------------------------
# Kubernetes Provider
#---------------------------------------------------------------

provider "kubernetes" {
  host                   = "https://${var.cluster_endpoint}"
  cluster_ca_certificate = base64decode(nonsensitive(var.cluster_ca_certificate))
  token                  = data.google_client_config.default.access_token
}

#---------------------------------------------------------------
# Helm Provider
#---------------------------------------------------------------

provider "helm" {
  kubernetes = {
    host                   = "https://${var.cluster_endpoint}"
    cluster_ca_certificate = base64decode(nonsensitive(var.cluster_ca_certificate))
    token                  = data.google_client_config.default.access_token
  }
}
