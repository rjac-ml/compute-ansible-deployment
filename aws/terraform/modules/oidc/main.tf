# GitHub OIDC Provider for AWS
# Allows GitHub Actions to assume AWS roles without long-term credentials

locals {
  account_id = var.account_id
  partition  = var.partition
  region     = var.region
}

# GitHub Actions OIDC Provider (pre-existing, account-level singleton)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# IAM Role for GitHub Actions CI/CD
# This role can be assumed by GitHub Actions workflows
resource "aws_iam_role" "github_actions" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              for branch in var.github_trust_branches :
              "repo:${var.github_org}/${var.github_repo_prefix}-*:${branch}"
            ]
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name    = var.role_name
    Purpose = "github-actions-cicd"
  })
}

# Base policy for EKS access (describe clusters)
resource "aws_iam_role_policy" "eks_access" {
  name = "eks-access"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/*"
      }
    ]
  })
}

# Terragrunt state bucket access
resource "aws_iam_role_policy" "terragrunt_state" {
  name = "terragrunt-state"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBucketManagement"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          for env in var.state_environments :
          "arn:${local.partition}:s3:::${var.state_bucket_prefix}-${env}"
        ]
      },
      {
        Sid    = "StateBucketObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          for env in var.state_environments :
          "arn:${local.partition}:s3:::${var.state_bucket_prefix}-${env}/*"
        ]
      },
      {
        Sid    = "DataBucketManagement"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:${local.partition}:s3:::${var.data_bucket_prefix}-*",
          "arn:${local.partition}:s3:::${var.data_bucket_prefix}-*/*",
        ]
      }
    ]
  })
}

# Infrastructure provisioning permissions — scoped per service
resource "aws_iam_role_policy" "infra_provisioning" {
  name = "infra-provisioning"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EKS — scoped to account + region
      {
        Sid    = "EKS"
        Effect = "Allow"
        Action = ["eks:*"]
        Resource = [
          "arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/*",
          "arn:${local.partition}:eks:${local.region}:${local.account_id}:nodegroup/*/*/*",
          "arn:${local.partition}:eks:${local.region}:${local.account_id}:addon/*/*/*",
          "arn:${local.partition}:eks:${local.region}:${local.account_id}:fargateprofile/*/*/*",
          "arn:${local.partition}:eks:${local.region}:${local.account_id}:podidentityassociation/*/*",
          "arn:${local.partition}:eks:${local.region}:${local.account_id}:access-entry/*/*/*",
        ]
      },
      # EKS read-only actions require Resource = * (e.g. DescribeAddonVersions)
      {
        Sid    = "EKSReadOnly"
        Effect = "Allow"
        Action = [
          "eks:DescribeAddonVersions",
          "eks:DescribeAddonConfiguration",
        ]
        Resource = "*"
      },
      # EC2 / VPC — Resource=* required because EKS node groups
      # reference public AMIs (no account ID in ARN) and
      # CreateNodegroup validates ec2:RunInstances on all resource types
      {
        Sid      = "EC2"
        Effect   = "Allow"
        Action   = ["ec2:*"]
        Resource = "*"
      },
      # ELB — scoped to account + region
      {
        Sid      = "ELB"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*"]
        Resource = "arn:${local.partition}:elasticloadbalancing:${local.region}:${local.account_id}:*"
      },
      # ELB describe actions require Resource = *
      {
        Sid    = "ELBReadOnly"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:Describe*",
        ]
        Resource = "*"
      },
      # IAM — global service, scoped to account
      {
        Sid    = "IAM"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PassRole",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile",
          "iam:ListInstanceProfilesForRole",
          "iam:ListInstanceProfileTags",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:CreateGroup",
          "iam:DeleteGroup",
          "iam:GetGroup",
          "iam:AttachGroupPolicy",
          "iam:DetachGroupPolicy",
          "iam:ListAttachedGroupPolicies",
          "iam:CreateServiceLinkedRole",
          "iam:TagPolicy",
          "iam:UntagPolicy",
          "iam:ListPolicyTags",
          "iam:PutGroupPolicy",
          "iam:DeleteGroupPolicy",
          "iam:GetGroupPolicy",
          "iam:ListGroupPolicies",
          "iam:UpdateAssumeRolePolicy",
          "iam:ListRoleTags",
        ]
        Resource = "arn:${local.partition}:iam::${local.account_id}:*"
      },
      # STS — identity check
      {
        Sid      = "STS"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
      # CloudWatch Logs — scoped to account + region
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:TagLogGroup",
          "logs:TagResource",
          "logs:ListTagsForResource",
          "logs:ListTagsLogGroup",
        ]
        Resource = "arn:${local.partition}:logs:${local.region}:${local.account_id}:*"
      },
      # KMS — manage existing keys (scoped to account + region)
      {
        Sid    = "KMS"
        Effect = "Allow"
        Action = [
          "kms:CreateAlias",
          "kms:DeleteAlias",
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListResourceTags",
          "kms:TagResource",
          "kms:ScheduleKeyDeletion",
          "kms:PutKeyPolicy",
          "kms:EnableKeyRotation",
        ]
        Resource = "arn:${local.partition}:kms:${local.region}:${local.account_id}:*"
      },
      # KMS CreateKey + ListAliases require Resource = *
      {
        Sid    = "KMSGlobal"
        Effect = "Allow"
        Action = [
          "kms:CreateKey",
          "kms:ListAliases",
        ]
        Resource = "*"
      },
      # SSM — scoped to account + region
      {
        Sid      = "SSM"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:*"
      },
      # SSM — AWS public parameters (no account ID in ARN)
      # EKS module reads /aws/service/eks/optimized-ami/* to resolve AMI IDs
      {
        Sid      = "SSMPublicParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:${local.partition}:ssm:${local.region}::parameter/aws/service/*"
      },
      # RDS (subnet groups) — scoped to account + region
      {
        Sid    = "RDS"
        Effect = "Allow"
        Action = [
          "rds:CreateDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:DescribeDBSubnetGroups",
          "rds:ModifyDBSubnetGroup",
          "rds:AddTagsToResource",
          "rds:RemoveTagsFromResource",
          "rds:ListTagsForResource",
        ]
        Resource = "arn:${local.partition}:rds:${local.region}:${local.account_id}:*"
      },
      # Route 53 — private hosted zones for internal DNS
      {
        Sid    = "Route53"
        Effect = "Allow"
        Action = [
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetChange",
          "route53:ChangeTagsForResource",
          "route53:ListTagsForResource",
          "route53:AssociateVPCWithHostedZone",
          "route53:DisassociateVPCFromHostedZone",
        ]
        Resource = "*"
      },
    ]
  })
}
