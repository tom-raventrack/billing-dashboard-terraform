output "smtp_host" {
  value = "email-smtp.${data.aws_region.current.region}.amazonaws.com"
}

output "smtp_secret_arn" {
  description = "JSON document with username and password keys."
  value       = aws_secretsmanager_secret.smtp.arn

  # ECS must not start tasks against the secret before it has a value.
  depends_on = [aws_secretsmanager_secret_version.smtp]
}

output "identity_arn" {
  value = aws_sesv2_email_identity.domain.arn
}

output "dkim_records" {
  description = "CNAME records that verify the domain; add them in the DNS account."
  value = [
    for token in aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens : {
      name  = "${token}._domainkey.${var.domain}"
      type  = "CNAME"
      value = "${token}.dkim.amazonses.com"
    }
  ]
}
