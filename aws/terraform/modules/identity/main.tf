locals {
  cluster_name                                 = var.cluster_name
  aws_load_balancer_controller_service_account = "aws-load-balancer-controller-sa"
  aws_load_balancer_controller_namespace       = "kube-system"
}

module "aws_load_balancer_controller_pod_identity" {
  count   = var.enable_aws_load_balancer_controller ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.2"

  name                            = "aws-load-balancer-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    aws_load_balancer_controller = {
      cluster_name    = local.cluster_name
      namespace       = local.aws_load_balancer_controller_namespace
      service_account = local.aws_load_balancer_controller_service_account
    }
  }
  tags = var.tags
}


