# TODO: replace with this Terraform repository's GitHub path (owner/name).
github_infra_repository = "tom-raventrack/billing-dashboard-terraform"

# Defaults, shown here so they are easy to change. If state_bucket_name
# changes, update the backend block in envs/production/versions.tf to match.
name               = "billing-dashboard"
region             = "eu-west-1"
state_bucket_name  = "raventrack-billing-dashboard-tfstate"
github_environment = "production"
