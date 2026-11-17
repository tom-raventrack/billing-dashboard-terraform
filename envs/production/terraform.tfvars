domain_name = "dashboard-internal.raventrack.com"

# TODO: replace with the ARN of the issued ACM certificate for domain_name.
# Request it in this account in eu-west-1; the validation CNAME is added in
# the account that hosts the raventrack.com zone.
certificate_arn = "arn:aws:acm:eu-west-1:863518431717:certificate/4f6897f7-c15c-45f1-9a2e-fb46d0c26e48"

# TODO: replace with the Laravel application repository in the form GitHub
# uses in its OIDC token: owner@owner-id/name@repository-id
# (e.g. tom-raventrack@170417133/my-app@1234567890). See the README for how
# to find the IDs.
github_app_repository = "tom-raventrack@170417133/billing-dashboard-v3@1345988696"

# Phase 4 of the plan: set to false to prove the app on AWS with rolling
# deploys first, then flip to true for phase 6.
enable_blue_green = true
