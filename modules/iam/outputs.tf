output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "ecs_infrastructure_role_arn" {
  value = aws_iam_role.ecs_infrastructure.arn
}

output "github_build_role_arn" {
  value = aws_iam_role.github_build.arn
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
