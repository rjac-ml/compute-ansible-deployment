# Provider pins matching the rest of aws/terraform/modules/*/versions.tf
terraform {
  required_version = ">= 1.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
