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

variable "allow_destroy" {
  description = "Teardown switch. false (normal) keeps deletion protection on the load balancer and database and refuses to delete a non-empty uploads bucket or ECR repository. Set to true and apply before running terraform destroy."
  type        = bool
  default     = false
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
  description = "Laravel application repository, exactly as it appears in the OIDC token subject after 'repo:', e.g. owner@owner-id/name@repository-id."
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
    APP_KEY               = "app-key"
    GOOGLE_CLIENT_ID      = "google-client-id"
    GOOGLE_CLIENT_SECRET  = "google-client-secret"
    XERO_CLIENT_ID        = "xero-client-id"
    XERO_CLIENT_SECRET    = "xero-client-secret"
    HUBSPOT_CLIENT_ID     = "hubspot-client-id"
    HUBSPOT_CLIENT_SECRET = "hubspot-client-secret"
    HUBSPOT_APP_ID        = "hubspot-app-id"
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

variable "db_type" {
  description = "Which PostgreSQL to run: \"rds\" (single RDS for PostgreSQL instance), \"aurora\" (Aurora PostgreSQL, provisioned instances) or \"aurora-serverless\" (Aurora Serverless v2). Changing it replaces the database; see the README."
  type        = string
  default     = "rds"
}

variable "db_engine_version" {
  description = "PostgreSQL version. A major version (e.g. \"18\") uses the newest available minor version at creation; a full version such as \"18.6\" pins it exactly."
  type        = string
  default     = "18.6"
}

variable "db_instance_class" {
  description = "Instance class for db_type \"rds\" or \"aurora\". Aurora needs db.t4g.medium or larger."
  type        = string
  default     = "db.t4g.small"
}

variable "db_allocated_storage" {
  description = "db_type \"rds\" only: initial gp3 storage in GiB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "db_type \"rds\" only: storage autoscaling ceiling in GiB."
  type        = number
  default     = 100
}

variable "db_instance_count" {
  description = "Aurora types only: 1 is a single writer; 2 adds a reader in another AZ."
  type        = number
  default     = 1
}

variable "db_min_capacity" {
  description = "db_type \"aurora-serverless\" only: minimum ACUs."
  type        = number
  default     = 0.5
}

variable "db_max_capacity" {
  description = "db_type \"aurora-serverless\" only: maximum ACUs."
  type        = number
  default     = 2
}

# --- Alerts ----------------------------------------------------------------

variable "alert_email" {
  description = "Email address subscribed to the alerts topic. Null creates the topic without a subscription."
  type        = string
  default     = null
}

variable "enable_execute_command" {
  description = "Enable ECS Exec (`aws ecs execute-command`) on the web, worker and scheduler services."
  type        = bool
  default     = true
}
