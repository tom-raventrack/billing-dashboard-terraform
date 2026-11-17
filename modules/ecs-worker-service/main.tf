# A single-container service with no load balancer, deployed rolling.
# Used twice: once for the queue worker and once for the scheduler.

data "aws_region" "current" {}

locals {
  service_name = "${var.name}-${var.role}"

  environment = [for k, v in var.environment : { name = k, value = v }]
  secrets     = [for k, v in var.secrets : { name = k, valueFrom = v }]
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "${var.log_group_prefix}/${var.role}"
  retention_in_days = var.log_retention_days
}

# Initial revision only; CI registers a new one per release.
resource "aws_ecs_task_definition" "this" {
  family                   = local.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name        = "app"
      image       = var.app_image
      essential   = true
      command     = var.command
      environment = local.environment
      secrets     = local.secrets

      # SIGTERM, then SIGKILL after this many seconds (Fargate maximum: 120).
      stopTimeout = var.stop_timeout

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = var.role
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name            = local.service_name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  propagate_tags                     = "SERVICE"
  enable_execute_command             = var.enable_execute_command

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}
