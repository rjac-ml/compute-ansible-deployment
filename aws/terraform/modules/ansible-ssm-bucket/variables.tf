# Inputs for the Ansible SSM staging bucket
#
# This bucket is REQUIRED by the amazon.aws.aws_ssm Ansible connection plugin
# (https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ssm_connection.html).
# It stages file payloads in transit between the GitHub Actions runner and
# the SSM-managed EC2 instances. It is NOT a binary mirror, NOT a config store,
# and NOT a long-lived data store — see lifecycle config in main.tf.

variable "account_id" {
  type        = string
  description = "AWS account ID hosting the bucket. Used in the bucket name to make it globally unique."
}

variable "region" {
  type        = string
  description = "AWS region where the bucket is created. Used in the bucket name to keep one bucket per region."
}

variable "ec2_instance_role_arn" {
  type        = string
  description = "ARN of the EC2 instance-profile role from the ec2-extended module. The bucket policy grants this role read/write/list access so the SSM agent on each target host can stage and retrieve file payloads during a playbook run."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged onto the bucket. Provider-level default_tags (set by root.hcl) are applied automatically."
}
