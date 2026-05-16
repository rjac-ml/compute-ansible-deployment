data "aws_caller_identity" "current" {}

# Admin Role - For human administrators
resource "aws_iam_role" "admin" {
  name = "${local.cluster_name}-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action    = "sts:AssumeRole"
        Condition = {}
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-admin"
    Type = "human-access"
  })
}

# Developer Role - For engineers with limited access
resource "aws_iam_role" "developer" {
  name = "${local.cluster_name}-developer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action    = "sts:AssumeRole"
        Condition = {}
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-developer"
    Type = "human-access"
  })
}

# EKS describe policy for both roles
resource "aws_iam_role_policy" "eks_access" {
  for_each = {
    admin     = aws_iam_role.admin.id
    developer = aws_iam_role.developer.id
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

# Admin Group
resource "aws_iam_group" "admin" {
  count = var.create_access_groups ? 1 : 0
  name  = "${local.cluster_name}-admin"
}

resource "aws_iam_group_policy" "admin_assume" {
  count = var.create_access_groups ? 1 : 0
  name  = "${local.cluster_name}-assume-admin"
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

# Developer Group
resource "aws_iam_group" "developer" {
  count = var.create_access_groups ? 1 : 0
  name  = "${local.cluster_name}-developer"
}

resource "aws_iam_group_policy" "developer_assume" {
  count = var.create_access_groups ? 1 : 0
  name  = "${local.cluster_name}-assume-developer"
  group = aws_iam_group.developer[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.developer.arn
      }
    ]
  })
}
