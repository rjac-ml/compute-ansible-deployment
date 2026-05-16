variable "name" {
  type        = string
  description = "Base name for all resources"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, stage, prod)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to deploy instances into"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block for security group rules"
}

variable "private_subnets" {
  type        = list(string)
  description = "List of private subnet IDs (instances are distributed across these)"
}

variable "instances_per_az" {
  type        = number
  description = "Number of on-demand instances to deploy per availability zone (1 instance per private subnet)"
  default     = 1
}

variable "instance_type" {
  type        = string
  description = "Default EC2 instance type (used unless overridden per-subnet by instance_type_overrides)"
  default     = "t3.micro"
}

variable "instance_type_overrides" {
  type        = map(string)
  # Override instance type per subnet index (0-based). Useful for AZs with limited Nitro support.
  # Example: { "4" = "t2.micro" } overrides the 5th subnet (us-east-1e) to use t2.micro
  description = "Map of subnet index to instance type override for AZs with limited instance type support"
  default     = {}
}

variable "data_volume_size" {
  type        = number
  description = "Size in GB for the data EBS volume"
  default     = 50
}

variable "ami_id" {
  type        = string
  description = "AMI ID override. If empty, latest Amazon Linux 2023 is used."
  default     = ""
}

variable "enable_dns" {
  type        = bool
  description = "Create Route 53 private hosted zone + DNS records for instance resolution"
  default     = true
}

variable "dns_zone_name" {
  type        = string
  description = "Route 53 private hosted zone domain name"
  default     = "compute-ansible.internal"
}

variable "deploy_id" {
  type        = string
  description = "Unique identifier for this deployment run (e.g., git SHA or timestamp). Used to identify stale instances."
  default     = ""
}

variable "enable_s3_bucket" {
  type        = bool
  description = "Create an S3 bucket for shared artifacts (config, data exchange)"
  default     = true
}

variable "s3_bucket_name" {
  type        = string
  description = "S3 bucket name override. If empty, auto-generated as compute-ansible-<region>-<env>"
  default     = ""
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "deployment_code" {
  type        = string
  description = "Unique deployment identifier for tag-based service discovery (format: versionmesh-account-region)"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources"
  default     = {}
}
