data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}
data "aws_partition" "current" {}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  region = var.region
}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}
