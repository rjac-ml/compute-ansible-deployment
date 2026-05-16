variable "name" {
  type        = string
  description = "Name of the cluster"
}

variable "environment" {
  type        = string
  description = "Environment of the cluster"
}

variable "enable_aws_load_balancer_controller" {
  type        = bool
  description = "Enable AWS Load Balancer Controller"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the resources"
}

variable "cluster_name" {
  type        = string
  description = "Name of the cluster"
}