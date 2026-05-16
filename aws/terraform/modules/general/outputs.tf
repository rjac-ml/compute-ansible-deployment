output "lbc_helm_release_version" {
  description = "Version of the AWS LBC Helm chart deployed"
  value       = var.enable_aws_load_balancer_controller ? helm_release.aws_load_balancer_controller[0].version : null
}

output "secrets_store_csi_enabled" {
  description = "Whether Secrets Store CSI Driver is enabled"
  value       = var.enable_secrets_store_csi
}
