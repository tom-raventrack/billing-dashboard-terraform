output "smtp_host" {
  value = "email-smtp.${data.aws_region.current.region}.amazonaws.com"
}

output "smtp_secret_arn" {
  description = "JSON document with username and password keys."
  value       = aws_secretsmanager_secret.smtp.arn

  # ECS must not start tasks against the secret before it has a value.
  depends_on = [aws_secretsmanager_secret_version.smtp]
}
