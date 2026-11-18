data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# PostgreSQL
# Holds app data plus the jobs, failed_jobs, sessions and cache tables.
#
# db_type picks one of:
#   rds               - a single RDS for PostgreSQL instance (no replica)
#   aurora            - Aurora PostgreSQL cluster on provisioned instances
#   aurora-serverless - Aurora PostgreSQL Serverless v2 cluster
# Only the resources for the chosen type are created. Changing the type
# replaces the database; data is not carried across.
# ---------------------------------------------------------------------------

locals {
  is_rds    = var.db_type == "rds"
  is_aurora = !local.is_rds

  db_engine = local.is_rds ? "postgres" : "aurora-postgresql"

  aurora_instance_class = var.db_type == "aurora-serverless" ? "db.serverless" : var.db_instance_class
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.private_subnet_ids
}

# The description is left as it was: changing a security group's description
# replaces the group.
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

# Resolves a major version such as "18" to the newest minor version AWS
# currently offers in this region, so the code never names a minor version
# that has been withdrawn. A full version such as "18.6" is used exactly.
data "aws_rds_engine_version" "postgres" {
  engine  = local.db_engine
  version = var.db_engine_version
  latest  = true
}

# --- RDS for PostgreSQL (db_type = "rds") -----------------------------------

resource "aws_db_instance" "this" {
  count = local.is_rds ? 1 : 0

  identifier     = var.name
  engine         = local.db_engine
  engine_version = data.aws_rds_engine_version.postgres.version_actual
  instance_class = var.db_instance_class
  db_name        = var.db_name
  username       = var.db_master_username

  # RDS generates and rotates the password in Secrets Manager, so it never
  # appears in Terraform state.
  manage_master_user_password = true

  # A single writer: no standby, no read replica.
  multi_az            = false
  publicly_accessible = false

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  storage_type          = "gp3"
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_encrypted     = true

  backup_retention_period = var.db_backup_retention_days
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true

  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    # Minor versions move during maintenance windows, and the lookup above
    # returns a newer one as AWS releases them; neither should trigger a change.
    ignore_changes = [engine_version]
  }
}

# --- Aurora PostgreSQL (db_type = "aurora" or "aurora-serverless") ----------

resource "aws_rds_cluster" "this" {
  count = local.is_aurora ? 1 : 0

  cluster_identifier = var.name
  engine             = local.db_engine
  engine_mode        = "provisioned"
  engine_version     = data.aws_rds_engine_version.postgres.version_actual
  database_name      = var.db_name
  master_username    = var.db_master_username

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

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.db_type == "aurora-serverless" ? [1] : []

    content {
      min_capacity = var.db_min_capacity
      max_capacity = var.db_max_capacity
    }
  }

  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "aws_rds_cluster_instance" "this" {
  count = local.is_aurora ? var.db_instance_count : 0

  identifier         = "${var.name}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this[0].id
  engine             = aws_rds_cluster.this[0].engine
  engine_version     = aws_rds_cluster.this[0].engine_version
  instance_class     = local.aurora_instance_class

  db_subnet_group_name       = aws_db_subnet_group.this.name
  auto_minor_version_upgrade = true

  lifecycle {
    ignore_changes = [engine_version]
  }
}

# The Aurora cluster used to be a single resource without count.
moved {
  from = aws_rds_cluster.this
  to   = aws_rds_cluster.this[0]
}

# ---------------------------------------------------------------------------
# S3 bucket for the Laravel "s3" filesystem disk
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "uploads" {
  bucket        = "${var.name}-uploads-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.uploads_force_destroy
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
