variable "name" {
  type        = string
  description = "Name of the VPC"
}

variable "environment" {
  type        = string
  description = "Environment of the VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "availability_zones_count" {
  type        = number
  description = "Number of availability zones"
}

variable "enable_database_subnets" {
  type        = bool
  description = "Enable database subnets"
  default     = false
}

variable "secondary_cidr_blocks" {
  type        = list(string)
  description = "Secondary CIDR blocks for EKS Data Plane"
  default     = []
}

variable "single_nat_gateway" {
  type        = bool
  description = "Enable single NAT gateway"
  default     = false
}

variable "public_subnets" {
  type        = list(string)
  description = "Public subnets"
  default     = []
}

variable "private_subnets" {
  type        = list(string)
  description = "Private subnets"
  default     = []
}

variable "azs" {
  type        = list(string)
  description = "Availability zones"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags for the VPC"
  default     = {}
}
