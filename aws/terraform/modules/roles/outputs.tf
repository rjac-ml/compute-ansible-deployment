output "admin_role_arn" {
  description = "ARN of the EKS admin role (for human access)"
  value       = aws_iam_role.admin.arn
}

output "admin_role_name" {
  description = "Name of the EKS admin role"
  value       = aws_iam_role.admin.name
}

output "cicd_role_arn" {
  description = "ARN of the EKS CI/CD role (for Terraform/ArgoCD provisioning)"
  value       = aws_iam_role.cicd.arn
}

output "cicd_role_name" {
  description = "Name of the EKS CI/CD role"
  value       = aws_iam_role.cicd.name
}

output "admin_group_name" {
  description = "Name of the IAM group for admins (if created)"
  value       = var.create_access_groups ? aws_iam_group.admin[0].name : null
}

output "developer_group_name" {
  description = "Name of the IAM group for developers (if created)"
  value       = var.create_access_groups ? aws_iam_group.developer[0].name : null
}

output "kubeconfig_admin_command" {
  description = "Command to configure kubectl for admin access"
  value       = "aws eks update-kubeconfig --name ${var.name}-${var.environment} --role-arn ${aws_iam_role.admin.arn}"
}

output "kubeconfig_cicd_command" {
  description = "Command to configure kubectl for CI/CD access"
  value       = "aws eks update-kubeconfig --name ${var.name}-${var.environment} --role-arn ${aws_iam_role.cicd.arn}"
}
