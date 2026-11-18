resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# One security group shared by web, worker, scheduler and one-off migration
# tasks. Only the ALB may open connections to it.
resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "ECS tasks"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-tasks" }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "nginx from the ALB"
  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.web_port
  to_port                      = var.web_port
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.tasks.id
  description       = "Outbound: PostgreSQL, ECR, S3, Secrets Manager, CloudWatch, third-party APIs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
