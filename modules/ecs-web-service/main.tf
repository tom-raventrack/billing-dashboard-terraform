data "aws_region" "current" {}

locals {
  service_name = "${var.name}-web"

  environment = [for k, v in var.environment : { name = k, value = v }]
  secrets     = [for k, v in var.secrets : { name = k, valueFrom = v }]
}

# ---------------------------------------------------------------------------
# Logs: one group per container
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "${var.log_group_prefix}/web-nginx"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "${var.log_group_prefix}/web-app"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# Task definition: nginx (ALB target) in front of PHP-FPM on 127.0.0.1:9000
#
# This is the *initial* revision. CI registers a new revision per release with
# the new image tags, and the service ignores task_definition changes.
# ---------------------------------------------------------------------------

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
      name      = "nginx"
      image     = var.nginx_image
      essential = true

      portMappings = [
        { containerPort = var.container_port, protocol = "tcp" }
      ]

      dependsOn = [
        { containerName = "app", condition = "HEALTHY" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.nginx.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "nginx"
        }
      }
    },
    {
      name        = "app"
      image       = var.app_image
      essential   = true
      environment = local.environment
      secrets     = local.secrets

      # PHP-FPM speaks FastCGI, not HTTP, so check that the port accepts
      # connections. startPeriod covers `php artisan optimize` in the entrypoint.
      healthCheck = {
        command     = ["CMD-SHELL", "php -r 'exit(@fsockopen(\"127.0.0.1\", 9000) ? 0 : 1);'"]
        interval    = 10
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])
}

# ---------------------------------------------------------------------------
# Alarms: ALB-wide, so they follow traffic across blue and green. The first
# two also act as deployment rollback triggers.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${local.service_name}-target-5xx"
  alarm_description   = "Web targets are returning 5xx responses"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_5xx_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "response_time_p95" {
  alarm_name          = "${local.service_name}-response-time-p95"
  alarm_description   = "Web p95 target response time is high"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_response_time_seconds
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# Not a rollback trigger: the idle target group has no hosts at all.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  for_each = var.target_group_arn_suffixes

  alarm_name          = "${local.service_name}-unhealthy-hosts-${each.key}"
  alarm_description   = "Unhealthy web targets in the ${each.key} target group"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = each.value
  }
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "this" {
  name            = local.service_name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  propagate_tags                     = "SERVICE"
  enable_execute_command             = var.enable_execute_command

  deployment_controller {
    type = "ECS"
  }

  # Phase 4 of the plan runs with enable_blue_green = false (rolling); phase 6
  # flips it to true.
  deployment_configuration {
    strategy             = var.enable_blue_green ? "BLUE_GREEN" : "ROLLING"
    bake_time_in_minutes = var.enable_blue_green ? var.bake_time_in_minutes : null
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  alarms {
    enable   = true
    rollback = true
    alarm_names = [
      aws_cloudwatch_metric_alarm.target_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.response_time_p95.alarm_name,
    ]
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.blue_target_group_arn
    container_name   = "nginx"
    container_port   = var.container_port

    dynamic "advanced_configuration" {
      for_each = var.enable_blue_green ? [1] : []

      content {
        alternate_target_group_arn = var.green_target_group_arn
        production_listener_rule   = var.production_listener_rule_arn
        test_listener_rule         = var.test_listener_rule_arn
        role_arn                   = var.ecs_infrastructure_role_arn
      }
    }
  }

  lifecycle {
    # CI owns the running task definition; autoscaling owns the task count.
    ignore_changes = [task_definition, desired_count]
  }
}

# ---------------------------------------------------------------------------
# Autoscaling
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.service_name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
