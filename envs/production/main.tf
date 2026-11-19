locals {
  name             = var.name
  log_group_prefix = "/ecs/${local.name}"

  # Fixed names, shared with the IAM module so it does not depend on the
  # services it grants access to.
  service_names = {
    web       = "${local.name}-web"
    worker    = "${local.name}-worker"
    scheduler = "${local.name}-scheduler"
  }

  app_image   = "${module.ecr.repository_urls["app"]}:${var.initial_image_tag}"
  nginx_image = "${module.ecr.repository_urls["nginx"]}:${var.initial_image_tag}"

  app_url = "https://${var.domain_name}"

  # SES sending domain, a subdomain of the dashboard's.
  mail_domain = "mail.${var.domain_name}"

  # Non-secret Laravel configuration, identical for web, worker and scheduler.
  app_environment = merge({
    APP_ENV              = var.environment
    APP_DEBUG            = "false"
    APP_URL              = local.app_url
    LOG_CHANNEL          = "stderr"
    DB_CONNECTION        = "pgsql"
    DB_HOST              = module.data.db_endpoint
    DB_PORT              = tostring(module.data.db_port)
    DB_DATABASE          = module.data.db_name
    DB_USERNAME          = module.data.db_master_username
    QUEUE_CONNECTION     = "database"
    DB_QUEUE_RETRY_AFTER = "180"
    CACHE_STORE          = "database"
    SESSION_DRIVER       = "database"
    FILESYSTEM_DISK      = "s3"
    UPLOADS_DISK         = "s3"
    AWS_BUCKET           = module.data.uploads_bucket_name
    AWS_DEFAULT_REGION   = var.region
    GOOGLE_REDIRECT_URI  = "${local.app_url}/auth/google/callback"
    GOOGLE_SSO_DOMAIN    = "raventrack.com"
    HUBSPOT_REDIRECT_URI = "${local.app_url}/api/hubspot/callback"
    MAIL_MAILER          = "smtp"
    MAIL_HOST            = module.mail.smtp_host
    MAIL_PORT            = "587"
    MAIL_FROM_ADDRESS    = "noreply@${local.mail_domain}"
  }, var.extra_environment)

  # Injected by ECS at task start from Secrets Manager.
  app_secrets = merge(
    { for env_name, secret in var.app_secrets : env_name => module.data.secret_arns[secret] },
    {
      DB_PASSWORD   = "${module.data.db_master_secret_arn}:password::"
      MAIL_USERNAME = "${module.mail.smtp_secret_arn}:username::"
      MAIL_PASSWORD = "${module.mail.smtp_secret_arn}:password::"
    },
  )
}

# ---------------------------------------------------------------------------
# Network, registry, load balancer
# ---------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  name     = local.name
  vpc_cidr = var.vpc_cidr
}

module "ecr" {
  source = "../../modules/ecr"

  name         = local.name
  force_delete = var.allow_destroy
}

module "alb" {
  source = "../../modules/alb"

  name                        = local.name
  vpc_id                      = module.network.vpc_id
  vpc_cidr                    = module.network.vpc_cidr
  public_subnet_ids           = module.network.public_subnet_ids
  certificate_arn             = var.certificate_arn
  test_listener_allowed_cidrs = var.test_listener_allowed_cidrs
  enable_deletion_protection  = !var.allow_destroy
}

# ---------------------------------------------------------------------------
# Cluster, data, IAM
# ---------------------------------------------------------------------------

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  alb_security_group_id = module.alb.security_group_id
}

module "data" {
  source = "../../modules/data"

  name                     = local.name
  vpc_id                   = module.network.vpc_id
  private_subnet_ids       = module.network.private_subnet_ids
  task_security_group_id   = module.ecs_cluster.task_security_group_id
  db_name                  = var.db_name
  db_type                  = var.db_type
  db_engine_version        = var.db_engine_version
  db_instance_class        = var.db_instance_class
  db_allocated_storage     = var.db_allocated_storage
  db_max_allocated_storage = var.db_max_allocated_storage
  db_instance_count        = var.db_instance_count
  db_min_capacity          = var.db_min_capacity
  db_max_capacity          = var.db_max_capacity
  secret_names             = toset(values(var.app_secrets))
  db_deletion_protection   = !var.allow_destroy
  uploads_force_destroy    = var.allow_destroy
}

# SES domain identity and an IAM user whose SMTP credentials the app sends with.
module "mail" {
  source = "../../modules/mail"

  name   = local.name
  domain = local.mail_domain
}

module "iam" {
  source = "../../modules/iam"

  name                     = local.name
  cluster_name             = local.name
  service_names            = values(local.service_names)
  task_definition_families = values(local.service_names)
  log_group_prefix         = local.log_group_prefix
  ecr_repository_arns      = values(module.ecr.repository_arns)
  secret_arns              = concat(values(module.data.secret_arns), [module.data.db_master_secret_arn, module.mail.smtp_secret_arn])
  uploads_bucket_arn       = module.data.uploads_bucket_arn
  metrics_namespace        = var.metrics_namespace
  github_repository        = var.github_app_repository
  github_environment       = var.environment
  github_build_refs        = var.github_build_refs
  enable_execute_command   = var.enable_execute_command
}

# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# Services: one image, three commands
# ---------------------------------------------------------------------------

module "web" {
  source = "../../modules/ecs-web-service"

  name               = local.name
  cluster_arn        = module.ecs_cluster.cluster_arn
  cluster_name       = module.ecs_cluster.cluster_name
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.ecs_cluster.task_security_group_id]
  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.task_role_arn

  enable_execute_command = var.enable_execute_command

  app_image   = local.app_image
  nginx_image = local.nginx_image
  environment = local.app_environment
  secrets     = local.app_secrets

  cpu              = var.web_cpu
  memory           = var.web_memory
  cpu_architecture = var.cpu_architecture
  desired_count    = var.web_min_capacity
  min_capacity     = var.web_min_capacity
  max_capacity     = var.web_max_capacity

  enable_blue_green            = var.enable_blue_green
  bake_time_in_minutes         = var.bake_time_in_minutes
  blue_target_group_arn        = module.alb.blue_target_group_arn
  green_target_group_arn       = module.alb.green_target_group_arn
  production_listener_rule_arn = module.alb.production_listener_rule_arn
  test_listener_rule_arn       = module.alb.test_listener_rule_arn
  ecs_infrastructure_role_arn  = module.iam.ecs_infrastructure_role_arn

  log_group_prefix          = local.log_group_prefix
  alb_arn_suffix            = module.alb.arn_suffix
  target_group_arn_suffixes = module.alb.target_group_arn_suffixes
  alarm_actions             = [aws_sns_topic.alerts.arn]

  # The target groups must be attached to a listener before the service is
  # created, and role policies must exist before ECS uses the roles.
  depends_on = [module.alb, module.iam]
}

module "worker" {
  source = "../../modules/ecs-worker-service"

  name               = local.name
  role               = "worker"
  cluster_arn        = module.ecs_cluster.cluster_arn
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.ecs_cluster.task_security_group_id]
  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.task_role_arn

  enable_execute_command = var.enable_execute_command

  app_image   = local.app_image
  environment = local.app_environment
  secrets     = local.app_secrets

  # Keep ordered: --timeout (110) < stop_timeout (120) < DB_QUEUE_RETRY_AFTER (180).
  command      = ["php", "artisan", "queue:work", "database", "--tries=3", "--timeout=110", "--max-time=3600"]
  stop_timeout = 120

  cpu              = var.worker_cpu
  memory           = var.worker_memory
  cpu_architecture = var.cpu_architecture
  desired_count    = var.worker_desired_count

  log_group_prefix = local.log_group_prefix

  depends_on = [module.iam]
}

module "scheduler" {
  source = "../../modules/ecs-worker-service"

  name               = local.name
  role               = "scheduler"
  cluster_arn        = module.ecs_cluster.cluster_arn
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.ecs_cluster.task_security_group_id]
  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.task_role_arn

  enable_execute_command = var.enable_execute_command

  app_image   = local.app_image
  environment = local.app_environment
  secrets     = local.app_secrets

  command = ["php", "artisan", "schedule:work"]

  cpu_architecture = var.cpu_architecture

  # The scheduler must run exactly once: stop the old task before starting
  # the new one, and never scale above one.
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  log_group_prefix = local.log_group_prefix

  depends_on = [module.iam]
}
