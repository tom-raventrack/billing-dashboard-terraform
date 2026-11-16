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
  description = "Security group of the ECS tasks allowed to reach Aurora."
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

variable "db_engine_version" {
  description = "Aurora PostgreSQL version. Check it is available in the region before the first apply."
  type        = string
  default     = "16.6"
}

variable "db_min_capacity" {
  description = "Serverless v2 minimum ACUs."
  type        = number
  default     = 0.5
}

variable "db_max_capacity" {
  description = "Serverless v2 maximum ACUs."
  type        = number
  default     = 2
}

variable "db_instance_count" {
  description = "Cluster instances. 1 is a single writer; 2 adds a reader in another AZ for failover."
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
