locals {
  # Exactly one of these lists has an element, depending on db_type.
  db_rds    = one(aws_db_instance.this)
  db_aurora = one(aws_rds_cluster.this)
}

output "db_type" {
  value = var.db_type
}

# An RDS instance's `endpoint` attribute is host:port, so it uses `address`.
output "db_endpoint" {
  description = "Writer hostname, without the port."
  value       = local.is_rds ? local.db_rds.address : local.db_aurora.endpoint
}

output "db_port" {
  value = local.is_rds ? local.db_rds.port : local.db_aurora.port
}

output "db_name" {
  value = local.is_rds ? local.db_rds.db_name : local.db_aurora.database_name
}

output "db_master_username" {
  value = local.is_rds ? local.db_rds.username : local.db_aurora.master_username
}

output "db_master_secret_arn" {
  description = "RDS-managed secret; a JSON document with username and password keys."
  value       = local.is_rds ? local.db_rds.master_user_secret[0].secret_arn : local.db_aurora.master_user_secret[0].secret_arn
}

output "uploads_bucket_name" {
  value = aws_s3_bucket.uploads.bucket
}

output "uploads_bucket_arn" {
  value = aws_s3_bucket.uploads.arn
}

output "secret_arns" {
  description = "Map of secret short name to ARN."
  value       = { for k, s in aws_secretsmanager_secret.app : k => s.arn }
}
