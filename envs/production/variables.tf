variable "name" {
  description = "Project name, used as a prefix for every resource."
  type        = string
  default     = "billing-dashboard"
}

variable "environment" {
  description = "Environment name. Also the GitHub Environment allowed to deploy, and Laravel's APP_ENV."
  type        = string
  default     = "production"
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# --- DNS -------------------------------------------------------------------

variable "domain_name" {
  description = "Fully qualified domain name of the dashboard. Its DNS record lives in another AWS account and is not managed here."
  type        = string
}

variable "certificate_arn" {
  description = "ARN of an issued ACM certificate for domain_name, requested in this account and region and validated through the DNS account."
  type        = string
}

variable "test_listener_allowed_cidrs" {
  description = "IPv4 CIDRs allowed to reach the blue/green test listener on port 8443. Empty keeps it closed."
  type        = list(string)
  default     = []
}

# --- GitHub ----------------------------------------------------------------

variable "github_app_repository" {
  description = "Laravel application repository, as owner/name."
  type        = string
}

variable "github_build_refs" {
  description = "Git refs allowed to push images to ECR."
  type        = list(string)
  default     = ["refs/heads/main"]
}

# --- Application -----------------------------------------------------------

variable "initial_image_tag" {
  description = "Image tag for the first task definition revisions. Only used until CI registers its own revisions."
  type        = string
  default     = "bootstrap"
}

variable "app_secrets" {
  description = "Map of environment variable name to Secrets Manager secret short name. Terraform creates the secret; set its value outside Terraform."
  type        = map(string)
  default = {
    APP_KEY = "app-key"
  }
}

variable "extra_environment" {
  description = "Additional non-secret environment variables for every container."
  type        = map(string)
  default     = {}
}

variable "metrics_namespace" {
  description = "CloudWatch namespace the app publishes queue metrics to."
  type        = string
  default     = "BillingDashboard"
}

# --- Web -------------------------------------------------------------------

variable "enable_blue_green" {
  description = "false deploys web with the rolling strategy (plan phase 4); true switches to ECS native blue/green (phase 6)."
  type        = bool
  default     = true
}

variable "bake_time_in_minutes" {
  type    = number
  default = 10
}

variable "web_cpu" {
  type    = number
  default = 512
}

variable "web_memory" {
  type    = number
  default = 1024
}

variable "web_min_capacity" {
  type    = number
  default = 1
}

variable "web_max_capacity" {
  type    = number
  default = 3
}

# --- Worker ----------------------------------------------------------------

variable "worker_cpu" {
  type    = number
  default = 256
}

variable "worker_memory" {
  type    = number
  default = 512
}

variable "worker_desired_count" {
  type    = number
  default = 1
}

# --- Database --------------------------------------------------------------

variable "db_name" {
  type    = string
  default = "billing_dashboard"
}

variable "db_engine_version" {
  description = "Aurora PostgreSQL version."
  type        = string
  default     = "16.6"
}

variable "db_min_capacity" {
  type    = number
  default = 0.5
}

variable "db_max_capacity" {
  type    = number
  default = 2
}

# --- Alerts ----------------------------------------------------------------

variable "alert_email" {
  description = "Email address subscribed to the alerts topic. Null creates the topic without a subscription."
  type        = string
  default     = null
}
