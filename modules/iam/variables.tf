variable "name" {
  description = "Name prefix."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "service_names" {
  description = "ECS service names the deploy role may update."
  type        = list(string)
}

variable "task_definition_families" {
  description = "Task definition families the deploy role may run and tag."
  type        = list(string)
}

variable "log_group_prefix" {
  description = "CloudWatch log group prefix of the ECS containers, e.g. /ecs/billing-dashboard."
  type        = string
}

variable "ecr_repository_arns" {
  type = list(string)
}

variable "secret_arns" {
  description = "Secrets Manager ARNs the execution role may read at task start."
  type        = list(string)
}

variable "uploads_bucket_arn" {
  type = string
}

variable "metrics_namespace" {
  description = "CloudWatch namespace the app may publish custom metrics to."
  type        = string
}

variable "github_repository" {
  description = "Application repository, exactly as it appears in the OIDC token subject after 'repo:', e.g. owner@owner-id/name@repository-id."
  type        = string
}

variable "github_environment" {
  description = "GitHub Environment allowed to deploy."
  type        = string
  default     = "production"
}

variable "github_build_refs" {
  description = "Git refs allowed to push images, e.g. refs/heads/main or refs/tags/v*."
  type        = list(string)
  default     = ["refs/heads/main"]
}
