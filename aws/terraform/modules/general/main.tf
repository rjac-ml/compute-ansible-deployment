locals {
  lbc_service_account = "aws-load-balancer-controller-sa"
  lbc_namespace       = "kube-system"
}

#---------------------------------------------------------------
# Pod Identity Addons
#---------------------------------------------------------------

module "eks_pod_identity" {
  source                              = "../identity"
  name                                = var.name
  environment                         = var.environment
  enable_aws_load_balancer_controller = var.enable_aws_load_balancer_controller
  tags                                = var.tags
  cluster_name                        = var.cluster_name
}

#---------------------------------------------------------------
# AWS Load Balancer Controller - Helm Release
#---------------------------------------------------------------

resource "helm_release" "aws_load_balancer_controller" {
  count = var.enable_aws_load_balancer_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lbc_helm_chart_version
  namespace  = local.lbc_namespace
  wait       = true

  values = [yamlencode({
    clusterName = var.cluster_name
    serviceAccount = {
      create = true
      name   = local.lbc_service_account
    }
    region = var.region
    vpcId  = var.vpc_id
  })]

  depends_on = [module.eks_pod_identity]
}

#---------------------------------------------------------------
# Secrets Store CSI Driver + AWS Provider (ASCP)
# Chart v2.x bundles the CSI driver as a dependency
#---------------------------------------------------------------

resource "helm_release" "secrets_store_csi_provider_aws" {
  count = var.enable_secrets_store_csi ? 1 : 0

  name       = "secrets-store-csi-driver-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  version    = var.secrets_store_csi_provider_aws_version
  namespace  = "kube-system"
  wait       = true

  values = [yamlencode({
    secrets-store-csi-driver = {
      syncSecret = {
        enabled = true
      }
    }
  })]
}
