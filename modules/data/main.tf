data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Aurora PostgreSQL Serverless v2
# Holds app data plus the jobs, failed_jobs, sessions and cache tables.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Aurora PostgreSQL"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_tasks" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from ECS tasks"
  referenced_security_group_id = var.task_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.name
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.db_engine_version
  database_name      = var.db_name
  master_username    = var.db_master_username

  # RDS generates and rotates the password in Secrets Manager, so it never
  # appears in Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  storage_encrypted            = true
  backup_retention_period      = var.db_backup_retention_days
  preferred_backup_window      = "02:00-03:00"
  preferred_maintenance_window = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot        = true

  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = var.db_min_capacity
    max_capacity = var.db_max_capacity
  }

  lifecycle {
    # Minor versions move during maintenance windows.
    ignore_changes = [engine_version]
  }
}

resource "aws_rds_cluster_instance" "this" {
  count = var.db_instance_count

  identifier         = "${var.name}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  instance_class     = "db.serverless"

  db_subnet_group_name       = aws_db_subnet_group.this.name
  auto_minor_version_upgrade = true

  lifecycle {
    ignore_changes = [engine_version]
  }
}

# ---------------------------------------------------------------------------
# S3 bucket for the Laravel "s3" filesystem disk
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "uploads" {
  bucket = "${var.name}-uploads-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# Application secrets
# Terraform creates the containers only. Set the values outside Terraform
# (console or `aws secretsmanager put-secret-value`) so they never land in
# state. A task cannot start until every secret it references has a value.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app" {
  for_each = var.secret_names

  name                    = "${var.name}/${each.key}"
  recovery_window_in_days = 7
}
