variable "name" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "billing-dashboard"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Globally unique name of the Terraform state bucket. Must match the backend block in envs/*/versions.tf."
  type        = string
  default     = "raventrack-billing-dashboard-tfstate"
}

variable "github_infra_repository" {
  description = "GitHub repository holding this Terraform code, exactly as it appears in the OIDC token subject after 'repo:'. For this account that is owner@owner-id/name@repository-id."
  type        = string
}

variable "github_environment" {
  description = "GitHub Environment allowed to run terraform apply."
  type        = string
  default     = "production"
}
