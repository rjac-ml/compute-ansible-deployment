output "instance_ids" {
  description = "Instance IDs of all nodes"
  value       = [for v in aws_instance.node : v.id]
}

output "instance_details" {
  description = "Map of instance name to details (id, private_ip, az)"
  value = { for k, v in aws_instance.node : k => {
    id         = v.id
    private_ip = v.private_ip
    az         = v.availability_zone
  } }
}

output "security_group_id" {
  description = "Security group ID for mesh nodes"
  value       = aws_security_group.nodes.id
}

output "iam_role_arn" {
  description = "IAM role ARN for instance access"
  value       = aws_iam_role.instance.arn
}

output "dns_zone_name" {
  description = "Route 53 private hosted zone domain name"
  value       = var.enable_dns ? var.dns_zone_name : ""
}

output "dns_records" {
  description = "Map of instance name to FQDN"
  value = var.enable_dns ? {
    for k, v in aws_route53_record.node : k => v.fqdn
  } : {}
}

output "s3_bucket_name" {
  description = "S3 bucket name for mesh artifacts"
  value       = var.enable_s3_bucket ? aws_s3_bucket.mesh[0].id : ""
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN for mesh artifacts"
  value       = var.enable_s3_bucket ? aws_s3_bucket.mesh[0].arn : ""
}

output "deployment_code" {
  description = "Deployment code tag value for service discovery"
  value       = var.deployment_code
}
