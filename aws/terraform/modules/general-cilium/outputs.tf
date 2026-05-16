output "cilium_version" {
  description = "Installed Cilium Helm chart version"
  value       = helm_release.cilium.version
}

output "hubble_enabled" {
  description = "Whether Hubble observability is enabled"
  value       = var.enable_hubble
}
