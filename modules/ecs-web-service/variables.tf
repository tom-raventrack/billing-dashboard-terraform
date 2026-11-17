variable "name" {
  description = "Name prefix; the service and task family are <name>-web."
  type        = string
}

variable "cluster_arn" {
  type = string
}

variable "cluster_name" {
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
  description = "PHP-FPM image for the initial task definition revision, as repository:tag."
  type        = string
}

variable "nginx_image" {
  description = "nginx image for the initial task definition revision, as repository:tag."
  type        = string
}

variable "environment" {
  description = "Non-secret environment variables for the app container."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of environment variable name to Secrets Manager or SSM ARN."
  type        = map(string)
  default     = {}
}

variable "cpu" {
  description = "Task CPU units."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Task memory in MiB."
  type        = number
  default     = 1024
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64. Must match the architecture the images are built for."
  type        = string
  default     = "X86_64"
}

variable "container_port" {
  description = "Port nginx listens on."
  type        = number
  default     = 80
}

variable "desired_count" {
  description = "Initial task count; autoscaling manages it afterwards."
  type        = number
  default     = 1
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 3
}

variable "cpu_target_percent" {
  description = "Average CPU utilisation the autoscaling policy tracks."
  type        = number
  default     = 60
}

# --- Blue/green ------------------------------------------------------------

variable "enable_blue_green" {
  description = "true uses the ECS native BLUE_GREEN strategy; false uses ROLLING."
  type        = bool
  default     = true
}

variable "bake_time_in_minutes" {
  description = "How long blue stays running after traffic shifts to green."
  type        = number
  default     = 10
}

variable "blue_target_group_arn" {
  type = string
}

variable "green_target_group_arn" {
  type = string
}

variable "production_listener_rule_arn" {
  type = string
}

variable "test_listener_rule_arn" {
  type = string
}

variable "ecs_infrastructure_role_arn" {
  description = "Role ECS assumes to modify listener rules during blue/green."
  type        = string
}

# --- Observability ---------------------------------------------------------

variable "log_group_prefix" {
  description = "CloudWatch log group prefix, e.g. /ecs/billing-dashboard."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffixes" {
  description = "Map of blue/green to target group ARN suffix."
  type        = map(string)
}

variable "alarm_actions" {
  description = "SNS topic ARNs notified when an alarm changes state."
  type        = list(string)
  default     = []
}

variable "alarm_5xx_threshold" {
  description = "Target 5xx responses per minute that trip the alarm."
  type        = number
  default     = 10
}

variable "alarm_response_time_seconds" {
  description = "p95 target response time that trips the alarm."
  type        = number
  default     = 2
}
