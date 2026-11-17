data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  ecs_arn    = "arn:${local.partition}:ecs:${local.region}:${local.account_id}"

  # Built from names rather than resource attributes, so this module does not
  # depend on the ECS services (which themselves depend on these roles).
  service_arns = [
    for s in var.service_names : "${local.ecs_arn}:service/${var.cluster_name}/${s}"
  ]
  task_definition_arns = [
    for f in var.task_definition_families : "${local.ecs_arn}:task-definition/${f}:*"
  ]
}

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# ---------------------------------------------------------------------------
# Task execution role: pull images, read secrets, write logs
# ---------------------------------------------------------------------------

resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secret_arns
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "read-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# ---------------------------------------------------------------------------
# Task role: what the Laravel application itself may do
# ---------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  name               = "${var.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "UploadsBucket"
    actions   = ["s3:ListBucket"]
    resources = [var.uploads_bucket_arn]
  }

  statement {
    sid       = "UploadsObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.uploads_bucket_arn}/*"]
  }

  # Queue health metrics published by a scheduled command.
  statement {
    sid       = "QueueMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.metrics_namespace]
    }
  }

  # ECS Exec: the SSM agent in each task opens its session channels with the
  # task role. These actions do not support resource-level permissions.
  dynamic "statement" {
    for_each = var.enable_execute_command ? [1] : []

    content {
      sid = "EcsExec"
      actions = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "app"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# ---------------------------------------------------------------------------
# ECS infrastructure role: lets ECS rewrite ALB listener rules and target
# group registrations during a blue/green deployment
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_infrastructure" {
  name               = "${var.name}-ecs-infrastructure"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  role       = aws_iam_role.ecs_infrastructure.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

# ---------------------------------------------------------------------------
# GitHub Actions roles for the application repository (deploy.yml)
#   build  : pushes images to ECR; runs before the approval gate
#   deploy : migrates and deploys; only from the production environment
# ---------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_build_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for ref in var.github_build_refs : "repo:${var.github_repository}:ref:${ref}"]
    }
  }
}

resource "aws_iam_role" "github_build" {
  name               = "${var.name}-github-build"
  assume_role_policy = data.aws_iam_policy_document.github_build_trust.json
}

data "aws_iam_policy_document" "github_build" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "github_build" {
  name   = "ecr-push"
  role   = aws_iam_role.github_build.id
  policy = data.aws_iam_policy_document.github_build.json
}

data "aws_iam_policy_document" "github_deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_trust.json
}

data "aws_iam_policy_document" "github_deploy" {
  # These actions do not support resource-level permissions.
  statement {
    sid = "TaskDefinitions"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "TagTaskDefinitions"
    actions   = ["ecs:TagResource"]
    resources = local.task_definition_arns
  }

  statement {
    sid = "Services"
    actions = [
      "ecs:DescribeServices",
      "ecs:ListServiceDeployments",
      "ecs:UpdateService",
    ]
    resources = local.service_arns
  }

  statement {
    sid = "ServiceDeployments"
    actions = [
      "ecs:DescribeServiceDeployments",
      "ecs:DescribeServiceRevisions",
    ]
    resources = [
      "${local.ecs_arn}:service-deployment/${var.cluster_name}/*",
      "${local.ecs_arn}:service-revision/${var.cluster_name}/*",
    ]
  }

  # One-off migration task.
  statement {
    sid       = "RunMigrations"
    actions   = ["ecs:RunTask"]
    resources = local.task_definition_arns

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = ["${local.ecs_arn}:cluster/${var.cluster_name}"]
    }
  }

  statement {
    sid       = "WatchTasks"
    actions   = ["ecs:DescribeTasks"]
    resources = ["${local.ecs_arn}:task/${var.cluster_name}/*"]
  }

  statement {
    sid       = "ReadTaskLogs"
    actions   = ["logs:GetLogEvents"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${var.log_group_prefix}/*:log-stream:*"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "ecs-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
