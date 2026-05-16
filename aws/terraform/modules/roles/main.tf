# EKS Access Roles
# Creates IAM roles for human admin access and CI/CD provisioning

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Data source for GitHub OIDC provider (created in common/oidc)
data "aws_iam_openid_connect_provider" "github" {
  arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  partition       = data.aws_partition.current.partition
  github_oidc_arn = data.aws_iam_openid_connect_provider.github.arn
}

# Admin Role - For human administrators
resource "aws_iam_role" "admin" {
  name = "${var.name}-${var.environment}-eks-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:${local.partition}:iam::${local.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-eks-admin"
    Type = "human-access"
  })
}

# CI/CD Role - For Terraform/ArgoCD provisioning via GitHub Actions OIDC
resource "aws_iam_role" "cicd" {
  name = "${var.name}-${var.environment}-eks-cicd"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # GitHub Actions OIDC trust
      [{
        Effect = "Allow"
        Principal = {
          Federated = local.github_oidc_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/pixemilar-*:*"
          }
        }
      }],
      # Optional: Human access for debugging (if trusted principals specified)
      var.cicd_trusted_principal_arns != [] ? [{
        Effect = "Allow"
        Principal = {
          AWS = var.cicd_trusted_principal_arns
        }
        Action = "sts:AssumeRole"
      }] : []
    )
  })

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-eks-cicd"
    Type = "cicd-access"
  })
}

# Policy for EKS cluster access (describe clusters)
resource "aws_iam_role_policy" "eks_cluster_access" {
  for_each = {
    admin = aws_iam_role.admin.id
    cicd  = aws_iam_role.cicd.id
  }

  name = "eks-cluster-access"
  role = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

# Optional: IAM Groups for easier user management

# Admin Group - Users in this group can assume admin role
resource "aws_iam_group" "admin" {
  count = var.create_access_groups ? 1 : 0
  name  = "${var.name}-${var.environment}-eks-admin"
}

resource "aws_iam_group_policy" "admin_assume" {
  count = var.create_access_groups ? 1 : 0
  name  = "${var.name}-${var.environment}-eks-admin-assume"
  group = aws_iam_group.admin[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.admin.arn
      }
    ]
  })
}

# Developer Group - Users in this group can assume cicd role (for debugging)
resource "aws_iam_group" "developer" {
  count = var.create_access_groups ? 1 : 0
  name  = "${var.name}-${var.environment}-eks-developer"
}

resource "aws_iam_group_policy" "developer_assume" {
  count = var.create_access_groups ? 1 : 0
  name  = "${var.name}-${var.environment}-eks-developer-assume"
  group = aws_iam_group.developer[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.cicd.arn
      }
    ]
  })
}
