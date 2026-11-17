# This Terraform repository, exactly as it appears in the GitHub OIDC token's
# subject: owner@owner-id/name@repository-id. GitHub includes the numeric IDs
# so a renamed or recreated repository cannot reuse the trust.
github_infra_repository = "tom-raventrack@170417133/billing-dashboard-terraform@1459966530"

# Defaults, shown here so they are easy to change. If state_bucket_name
# changes, update the backend block in envs/production/versions.tf to match.
name               = "billing-dashboard"
region             = "eu-west-1"
state_bucket_name  = "raventrack-billing-dashboard-tfstate"
github_environment = "production"
