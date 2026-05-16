variable "name" {
  type        = string
  description = "The name of the EKS cluster."
}

variable "region" {
  type        = string
  description = "The AWS region to deploy the EKS cluster in."
}

variable "profile" {
  type        = string
  description = "The AWS profile to use for authentication."
}

variable "account_id" {
  type        = string
  description = "The AWS account ID."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the resources."
}

variable "availability_zones_count" {
  type        = number
  description = "The number of availability zones to deploy the EKS cluster in."
}
