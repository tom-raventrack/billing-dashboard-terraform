domain_name = "dashboard.internal.raventrack.com"

# TODO: replace with the ARN of the issued ACM certificate for domain_name.
# Request it in this account in eu-west-1; the validation CNAME is added in
# the account that hosts the raventrack.com zone.
certificate_arn = "CHANGE_ME"

# TODO: replace with the Laravel application repository (owner/name).
github_app_repository = "tom-raventrack/billing-dashboard-v3"

# Phase 4 of the plan: set to false to prove the app on AWS with rolling
# deploys first, then flip to true for phase 6.
enable_blue_green = true
