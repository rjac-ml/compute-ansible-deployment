output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "admin_role_arn" {
  value       = aws_iam_role.admin.arn
  description = "ARN of the EKS admin role"
}

output "developer_role_arn" {
  value       = aws_iam_role.developer.arn
  description = "ARN of the EKS developer role"
}

