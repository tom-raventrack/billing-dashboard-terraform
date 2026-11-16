output "db_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "db_port" {
  value = aws_rds_cluster.this.port
}

output "db_name" {
  value = aws_rds_cluster.this.database_name
}

output "db_master_username" {
  value = aws_rds_cluster.this.master_username
}

output "db_master_secret_arn" {
  description = "RDS-managed secret; a JSON document with username and password keys."
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
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
