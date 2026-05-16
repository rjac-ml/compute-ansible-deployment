data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(nonsensitive(var.cluster_certificate_authority_data))
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(nonsensitive(var.cluster_certificate_authority_data))
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
