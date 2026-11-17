output "state_bucket_name" {
  value = aws_s3_bucket.state.bucket
}

output "github_oidc_provider_arn" {
  value = data.aws_iam_openid_connect_provider.github.arn
}

output "terraform_plan_role_arn" {
  description = "Role for infra.yml on pull requests."
  value       = aws_iam_role.terraform_plan.arn
}

output "terraform_apply_role_arn" {
  description = "Role for infra.yml on merge to main (production environment)."
  value       = aws_iam_role.terraform_apply.arn
}
