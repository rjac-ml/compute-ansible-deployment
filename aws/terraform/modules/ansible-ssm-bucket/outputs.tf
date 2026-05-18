output "bucket_name" {
  description = "Name of the SSM staging bucket. Pass this to the amazon.aws.aws_ssm Ansible connection plugin as ansible_aws_ssm_bucket_name."
  value       = aws_s3_bucket.ssm_staging.id
}

output "bucket_arn" {
  description = "ARN of the SSM staging bucket."
  value       = aws_s3_bucket.ssm_staging.arn
}

output "bucket_region" {
  description = "Region the bucket lives in. Pass this to the Ansible plugin as ansible_aws_ssm_region."
  value       = var.region
}
