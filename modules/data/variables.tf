variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "task_security_group_id" {
  description = "Security group of the ECS tasks allowed to reach the database."
  type        = string
}

variable "db_name" {
  description = "Initial database name (letters, digits and underscores)."
  type        = string
}

variable "db_master_username" {
  type    = string
  default = "app"
}

variable "db_type" {
  description = "Which PostgreSQL to run: \"rds\" (a single RDS for PostgreSQL instance), \"aurora\" (Aurora PostgreSQL on provisioned instances) or \"aurora-serverless\" (Aurora PostgreSQL Serverless v2). Changing it replaces the database."
  type        = string
  default     = "rds"

  validation {
    condition     = contains(["rds", "aurora", "aurora-serverless"], var.db_type)
    error_message = "db_type must be \"rds\", \"aurora\" or \"aurora-serverless\"."
  }
}

variable "db_engine_version" {
  description = "PostgreSQL version for the chosen engine. A major version (e.g. \"18\") uses the newest available minor version at creation; a full version such as \"18.6\" pins it exactly. Must be offered by RDS for PostgreSQL or Aurora PostgreSQL, whichever db_type selects."
  type        = string
  default     = "18.6"
}

variable "db_instance_class" {
  description = "Instance class for db_type \"rds\" or \"aurora\" (ignored for \"aurora-serverless\", which uses db.serverless). Aurora PostgreSQL's smallest class is db.t4g.medium."
  type        = string
  default     = "db.t4g.small"

  validation {
    condition     = var.db_type != "aurora" || !contains(["db.t4g.micro", "db.t4g.small", "db.t3.micro", "db.t3.small"], var.db_instance_class)
    error_message = "Aurora PostgreSQL does not support micro or small instance classes; use db.t4g.medium or larger."
  }
}

variable "db_allocated_storage" {
  description = "db_type \"rds\" only: initial gp3 storage in GiB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "db_type \"rds\" only: storage autoscaling ceiling in GiB. Set equal to db_allocated_storage to turn autoscaling off."
  type        = number
  default     = 100
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

variable "db_instance_count" {
  description = "Aurora types only: cluster instances. 1 is a single writer; 2 adds a reader in another AZ for failover. db_type \"rds\" always runs a single instance."
  type        = number
  default     = 1
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_deletion_protection" {
  type    = bool
  default = true
}

variable "uploads_force_destroy" {
  description = "Allow the uploads bucket to be deleted while it still contains objects."
  type        = bool
  default     = false
}

variable "secret_names" {
  description = "Short names of Secrets Manager secrets to create as empty containers, e.g. app-key."
  type        = set(string)
  default     = ["app-key"]
}
