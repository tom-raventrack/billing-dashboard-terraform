# ---------------------------------------------------------------------------
# Security group
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internet-facing ALB"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP, redirected to HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# The test listener reaches the green task set before cut-over, so it is
# closed unless specific source ranges are allowed.
resource "aws_vpc_security_group_ingress_rule" "test" {
  for_each = toset(var.test_listener_allowed_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "Blue/green test listener"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.test_listener_port
  to_port           = var.test_listener_port
}

resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.alb.id
  description       = "To web tasks"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
}

# ---------------------------------------------------------------------------
# Certificate and DNS
#
# The raventrack.com hosted zone is in another AWS account, so neither is
# managed here. The ACM certificate is requested in this account and region,
# validated by a CNAME added in the DNS account, and passed in by ARN. The
# DNS account also holds the record pointing the domain at this ALB (see the
# dns_name and zone_id outputs).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Load balancer and target groups
# ---------------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection
}

resource "aws_lb_target_group" "web" {
  for_each = toset(["blue", "green"])

  name                 = "${var.name}-web-${each.key}"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = var.target_port
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# ---------------------------------------------------------------------------
# Listeners
#
# ECS blue/green works on listener *rules*, so each HTTPS listener has a
# catch-all rule that forwards to both target groups by weight. ECS rewrites
# the weights during a deployment; Terraform ignores those changes.
# ---------------------------------------------------------------------------

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "production" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.web["blue"].arn
        weight = 100
      }

      target_group {
        arn    = aws_lb_target_group.web["green"].arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.test_listener_port
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "test" {
  listener_arn = aws_lb_listener.test.arn
  priority     = 100

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.web["blue"].arn
        weight = 100
      }

      target_group {
        arn    = aws_lb_target_group.web["green"].arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}
