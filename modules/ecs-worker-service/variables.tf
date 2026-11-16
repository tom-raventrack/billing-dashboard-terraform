variable "name" {
  description = "Name prefix; the service and task family are <name>-<role>."
  type        = string
}

variable "role" {
  description = "What this service does, e.g. worker or scheduler."
  type        = string
}

variable "command" {
  description = "Container command, overriding the image default."
  type        = list(string)
}

variable "cluster_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "app_image" {
  description = "App image for the initial task definition revision, as repository:tag."
  type        = string
}

variable "environment" {
  description = "Non-secret environment variables."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of environment variable name to Secrets Manager or SSM ARN."
  type        = map(string)
  default     = {}
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "cpu_architecture" {
  type    = string
  default = "X86_64"
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "stop_timeout" {
  description = "Seconds between SIGTERM and SIGKILL. Must exceed the longest job timeout; 120 is the Fargate maximum."
  type        = number
  default     = 120

  validation {
    condition     = var.stop_timeout >= 2 && var.stop_timeout <= 120
    error_message = "stop_timeout must be between 2 and 120 seconds on Fargate."
  }
}

variable "deployment_minimum_healthy_percent" {
  description = "100 starts the new task before stopping the old one; 0 stops the old one first."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  type    = number
  default = 200
}

variable "log_group_prefix" {
  description = "CloudWatch log group prefix, e.g. /ecs/billing-dashboard."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}
