data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  identity_arn_prefix = "arn:${data.aws_partition.current.partition}:ses:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:identity"
}

# ---------------------------------------------------------------------------
# SMTP user for an SES domain identity that already exists and is verified
# outside Terraform. SES SMTP authenticates with an IAM access key: the key
# ID is the SMTP username and a password derived from the secret key is the
# SMTP password. Both are stored in Secrets Manager for ECS to inject.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "smtp" {
  name = "${var.name}-ses-smtp"
}

data "aws_iam_policy_document" "smtp" {
  statement {
    sid     = "SendFromDomain"
    actions = ["ses:SendRawEmail"]

    # identity/* rather than the domain alone: while the account is in the SES
    # sandbox, the recipient identity is authorised too.
    resources = ["${local.identity_arn_prefix}/*"]

    condition {
      test     = "StringLike"
      variable = "ses:FromAddress"
      values   = ["*@${var.domain}"]
    }
  }
}

resource "aws_iam_user_policy" "smtp" {
  name   = "ses-send"
  user   = aws_iam_user.smtp.name
  policy = data.aws_iam_policy_document.smtp.json
}

resource "aws_iam_access_key" "smtp" {
  user = aws_iam_user.smtp.name
}

resource "aws_secretsmanager_secret" "smtp" {
  name                    = "${var.name}/ses-smtp"
  description             = "SES SMTP credentials for ${aws_iam_user.smtp.name}. Managed by Terraform."
  recovery_window_in_days = 7
}

# ses_smtp_password_v4 is derived for the provider's region, so the SMTP host
# must be in the same region.
resource "aws_secretsmanager_secret_version" "smtp" {
  secret_id = aws_secretsmanager_secret.smtp.id
  secret_string = jsonencode({
    username = aws_iam_access_key.smtp.id
    password = aws_iam_access_key.smtp.ses_smtp_password_v4
  })
}
