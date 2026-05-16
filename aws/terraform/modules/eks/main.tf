locals {
  cluster_name = "${var.name}-${var.environment}"
  # Filter secondary CIDR subnets (starting with "100.")
  secondary_cidr_subnets = compact([for subnet_id, cidr_block in zipmap(var.private_subnets, var.private_subnets_cidr_blocks) :
  substr(cidr_block, 0, 4) == "100." ? subnet_id : null])

  base_addons = {
    for name, enabled in var.enable_cluster_addons :
    name => {} if enabled && !var.enable_eks_auto_mode
  }

  # Extended configurations used for specific addons with custom settings
  addon_overrides = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }

    eks-pod-identity-agent = {
      before_compute = true
    }
  }
  # Merge base with overrides
  cluster_addons = {
    for name, config in local.base_addons :
    name => merge(config, lookup(local.addon_overrides, name, {}))
  }

  # Access entries - admin and developer created internally, CI/CD passed externally
  cicd_access_entry = var.cicd_role_arn != "" ? {
    cicd_role = {
      principal_arn = var.cicd_role_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  } : {}

  access_entries = merge(
    {
      admin_role = {
        principal_arn = aws_iam_role.admin.arn
        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
      developer_role = {
        kubernetes_groups = ["developers"]
        principal_arn     = aws_iam_role.developer.arn
        policy_associations = {
          developer = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            access_scope = {
              type       = "namespace"
              namespaces = ["*"]
            }
          }
        }
      }
    },
    local.cicd_access_entry
  )
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  name = local.cluster_name

  kubernetes_version = var.cluster_version
  compute_config     = { enabled = var.enable_eks_auto_mode }
  addons             = local.cluster_addons

  # Optional
  endpoint_public_access = var.endpoint_public_access

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  vpc_id     = var.vpc_id
  subnet_ids = local.secondary_cidr_subnets

  # EKS Managed Node Group(s)
  eks_managed_node_groups = var.eks_managed_node_groups

  # Access Entries for admin and CI/CD roles
  access_entries = local.access_entries

  tags = var.tags
}

resource "aws_ec2_tag" "cluster_primary_security_group" {
  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.cluster_name
}
