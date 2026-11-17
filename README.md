# Billing dashboard infrastructure

Terraform for the billing dashboard: a Laravel app on ECS Fargate in eu-west-1, with a
blue/green web service, a rolling queue worker and a single scheduler.

- [Repository layout](#repository-layout)
- [What gets created](#what-gets-created)
- [Initial setup](#initial-setup): start here for a new AWS account
- [Day-to-day changes](#day-to-day-changes)
- [Tearing it down](#tearing-it-down)
- [GitHub Actions reference](#github-actions-reference)
- [Design notes](#design-notes)
- [Who owns what](#who-owns-what)
- [Not included](#not-included)

## Repository layout

```
bootstrap/          state bucket, Terraform CI roles (applied once, local state)
modules/
  network/          VPC, 2 public + 2 private subnets, one NAT gateway, S3 gateway endpoint
  ecr/              app and nginx repositories
  alb/              ALB, blue + green target groups, listeners and rules (certificate passed in by ARN)
  ecs-cluster/      Fargate cluster, shared task security group
  data/             Aurora PostgreSQL Serverless v2, uploads bucket, secret containers
  iam/              execution, task, ECS infrastructure and GitHub Actions roles
  ecs-web-service/  nginx + PHP-FPM task, blue/green service, autoscaling, rollback alarms
  ecs-worker-service/  single-container rolling service (used for worker and scheduler)
envs/
  production/       calls the modules; state key production/terraform.tfstate
.github/workflows/
  infra.yml         plans on pull requests, applies envs/production on merge to main
app-workflows/
  deploy.yml        release workflow to copy into the Laravel application repository
  iam/              reference JSON for the build and deploy roles (Terraform creates the real ones)
```

There are two Terraform configurations, each with its own `terraform.tfvars`:

| Configuration | Applied | State | Settings file |
| --- | --- | --- | --- |
| `bootstrap/` | Once, from your machine | Local file | `bootstrap/terraform.tfvars` |
| `envs/production/` | By CI on every merge to main | S3 bucket created by bootstrap | `envs/production/terraform.tfvars` |

## What gets created

Everything is in eu-west-1 and prefixed `billing-dashboard`.

### Bootstrap

| Resource | Name | Purpose |
| --- | --- | --- |
| S3 bucket | `raventrack-billing-dashboard-tfstate` | Terraform state for production; versioned, encrypted, private, TLS-only |
| IAM role | `billing-dashboard-terraform-plan` | Read-only role for pull request plans |
| IAM role | `billing-dashboard-terraform-apply` | Administrator role for applies, only from the `production` GitHub Environment |

### Production

| Area | Resources | Notes |
| --- | --- | --- |
| Network | 1 VPC (`10.0.0.0/16`), 2 public and 2 private subnets across 2 availability zones, internet gateway, 1 NAT gateway with an Elastic IP, 2 route tables, S3 gateway endpoint | Load balancer in public subnets; tasks and database in private ones |
| Container registry | 2 ECR repositories: `billing-dashboard/app`, `billing-dashboard/nginx` | Immutable tags, scan on push, keeps the last 30 images |
| Load balancer | 1 internet-facing ALB, 2 target groups (`web-blue`, `web-green`), 3 listeners (80 redirect, 443, 8443 test), 2 listener rules, 1 security group | ECS shifts traffic between the two target groups |
| ECS cluster | 1 Fargate cluster with Container Insights, 1 security group shared by all tasks | |
| Web service | `billing-dashboard-web`: service, task definition (nginx + PHP-FPM), autoscaling target and CPU policy (1 to 3 tasks), 2 log groups | Deploys blue/green |
| Worker service | `billing-dashboard-worker`: service, task definition, 1 log group | 1 task running `queue:work`; deploys rolling |
| Scheduler service | `billing-dashboard-scheduler`: service, task definition, 1 log group | 1 task running `schedule:work` |
| Database | 1 Aurora PostgreSQL Serverless v2 cluster with 1 instance (0.5 to 2 ACUs), subnet group, security group | App data, queue, sessions and cache; 7-day backups, deletion protection |
| Storage | 1 S3 bucket: `billing-dashboard-uploads-<account-id>` | Laravel uploads; versioned, encrypted, private |
| Secrets | `billing-dashboard/app-key` (empty until you set it), plus the database password secret that RDS creates and manages | |
| IAM | 5 roles: `ecs-execution`, `ecs-task`, `ecs-infrastructure`, `github-build`, `github-deploy` | The last two are assumed by the application repository's release workflow |
| Monitoring | 4 CloudWatch alarms (target 5xx, p95 response time, unhealthy hosts for blue and for green), 1 SNS topic `billing-dashboard-alerts` | The first two alarms also trigger deployment rollback |

### Used but not created by Terraform

- **GitHub OIDC provider:** one per AWS account, shared; only looked up.
- **ACM certificate:** requested by hand and passed in by ARN.
- **DNS records:** the dashboard record and the certificate validation CNAME live in another
  AWS account.

### Running costs

These bill continuously whether or not anyone uses the dashboard: the NAT gateway, the load
balancer, the three always-on Fargate tasks (web, worker, scheduler), and Aurora at its
0.5 ACU minimum. The rest is usage-based or negligible at this scale.

To list what is actually in state, as opposed to what the code describes (production needs
`terraform init` with AWS credentials first):

```bash
terraform -chdir=bootstrap state list
```

```bash
terraform -chdir=envs/production state list
```

## Initial setup

Work through the steps in order. Steps 1 to 5 create the infrastructure; steps 6 to 9 get the
application running on it.

### Before you start

You need:

- Terraform 1.10 or newer and the AWS CLI, with credentials for the target AWS account that
  can create IAM roles, S3 buckets and networking (administrator access is simplest).
- Admin access to this GitHub repository and to the Laravel application repository.
- Someone who can add records to the `raventrack.com` DNS zone, which lives in a different
  AWS account.

Confirm your credentials point at the right account before running anything:

```bash
aws sts get-caller-identity
```

### 1. Bootstrap the account

This creates the Terraform state bucket and the two roles the infrastructure workflow
assumes. It runs once, from your machine.

Check `bootstrap/terraform.tfvars`:

| Setting | Meaning |
| --- | --- |
| `github_infra_repository` | This repository, in the ID-qualified form GitHub uses in its OIDC tokens (see below). Only this repository can assume the Terraform roles. |
| `state_bucket_name` | Globally unique S3 bucket name. If you change it, change the `backend "s3"` block in `envs/production/versions.tf` to match. |
| `name`, `region`, `github_environment` | Defaults; leave as they are unless you have a reason to change them. |

**Repository names include numeric IDs.** GitHub identifies this account's repositories in
OIDC tokens as `owner@owner-id/name@repository-id`, for example
`tom-raventrack@170417133/billing-dashboard-terraform@1459966530`. The role trust policies
match that string exactly, so a plain `owner/name` fails with "Not authorized to perform
sts:AssumeRoleWithWebIdentity". The same applies to `github_app_repository` in step 4. To
find a repository's IDs, replace `OWNER/NAME` and read `owner_id` and `repository_id`:

```bash
curl -s https://api.github.com/repos/OWNER/NAME | jq '{owner_id: .owner.id, repository_id: .id}'
```

That works without signing in for public repositories. For a private one, read the same
`owner.id` and `id` fields with an authenticated request such as `gh api repos/OWNER/NAME`.

Then, from the repository root:

```bash
cd bootstrap
```

```bash
terraform init
```

```bash
terraform apply
```

```bash
terraform output
```

Keep the output; step 2 uses the two role ARNs.

- **Keep `bootstrap/terraform.tfstate` safe.** It is ignored by git and is the only record of
  these resources. Store a copy somewhere durable.
- **The GitHub OIDC provider is looked up, not created.** An account can have only one, and
  it is shared with anything else that uses GitHub OIDC, so bootstrap never manages or
  deletes it. In an account that does not have one yet, create it first:

```bash
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com
```

### 2. Configure this GitHub repository

In the repository's settings:

1. **Environments:** create an environment named `production` and add required reviewers.
   Nothing is applied to AWS without their approval.
2. **Secrets and variables > Actions > Variables:** add two repository variables from the
   bootstrap output. They are ARNs, not secrets.

| Variable | Bootstrap output |
| --- | --- |
| `AWS_TERRAFORM_PLAN_ROLE_ARN` | `terraform_plan_role_arn` |
| `AWS_TERRAFORM_APPLY_ROLE_ARN` | `terraform_apply_role_arn` |

### 3. Request the certificate

The `raventrack.com` zone is in another AWS account, so Terraform manages neither the
certificate nor the DNS records.

1. In this account, in **eu-west-1**, request a public ACM certificate for
   `dashboard.internal.raventrack.com` with DNS validation.
2. Ask the DNS account's owner to add the validation CNAME that ACM shows.
3. Wait for the certificate status to become **Issued**. The production apply fails if it is
   still pending.

Leave the validation CNAME in place afterwards: ACM uses it to renew the certificate
automatically.

### 4. Configure production

Edit `envs/production/terraform.tfvars`:

| Setting | Meaning |
| --- | --- |
| `certificate_arn` | ARN of the issued certificate from step 3. |
| `github_app_repository` | The Laravel application repository, in the ID-qualified form described in step 1. Only this repository can push images and deploy. |
| `domain_name` | Already set to `dashboard.internal.raventrack.com`. |
| `enable_blue_green` | `true` for blue/green. Set to `false` to start with rolling deploys and switch later. |

Optional settings, such as `alert_email` and task sizes, are listed in
`envs/production/variables.tf`.

### 5. Apply production

Open a pull request with the step 4 changes. The workflow posts the plan as a comment; review
it, merge, and approve the `production` deployment when prompted. The first apply takes around
15 minutes, mostly Aurora.

To run it from your machine instead:

```bash
cd envs/production
```

```bash
terraform init
```

```bash
terraform apply
```

When it finishes the ECS services exist, but their tasks cannot start until steps 7 and 9 are
done. That is expected. Read the outputs for the next steps:

```bash
terraform output
```

### 6. Point DNS at the load balancer

Ask the DNS account's owner to create a record for `dashboard.internal.raventrack.com` using
the `alb_dns` output: either a CNAME to `dns_name`, or a Route 53 alias A record using
`dns_name` and `zone_id`.

Repeat this if the load balancer is ever recreated, because its DNS name changes.

### 7. Set the secret values

Terraform creates each secret empty so that values never enter the state file. Every secret in
the `app_secret_arns` output needs a value before tasks can start. By default that is only
`APP_KEY`.

Generate a key in the Laravel application:

```bash
php artisan key:generate --show
```

Store it, replacing the placeholder with the generated value:

```bash
aws secretsmanager put-secret-value --region eu-west-1 --secret-id billing-dashboard/app-key --secret-string "base64:REPLACE_ME"
```

The database password needs no action: RDS generates and stores it.

### 8. Configure the application repository

In the Laravel application repository:

1. **Environments:** create an environment named `production` with required reviewers.
2. **Variables:** add two repository variables from the production output.

| Variable | Production output |
| --- | --- |
| `AWS_BUILD_ROLE_ARN` | `github_build_role_arn` |
| `AWS_DEPLOY_ROLE_ARN` | `github_deploy_role_arn` |

3. **Workflow:** copy `app-workflows/deploy.yml` from this repository to
   `.github/workflows/deploy.yml` in the application repository. Check the assumptions listed
   at the top of the file (Dockerfile targets `app` and `nginx`, PHP 8.3, Node 22).

### 9. Release for the first time

Merge to `main` in the application repository. The workflow tests, builds and pushes the
images, waits for approval, runs migrations and `app:setup-production`, then deploys web,
worker and scheduler. Once it finishes, the dashboard is live at `https://dashboard.internal.raventrack.com`.

Before real users arrive, practise a rollback by releasing an image whose `/up` route fails
and confirming traffic stays on the previous version.

## Day-to-day changes

**Infrastructure.** Change the Terraform, open a pull request, review the plan comment, merge,
and approve the apply. Before pushing, format and validate locally from the repository root.
`-backend=false` skips the state bucket, so this needs no AWS credentials.

```bash
terraform fmt -recursive
```

```bash
terraform -chdir=bootstrap init -backend=false && terraform -chdir=bootstrap validate
```

```bash
terraform -chdir=envs/production init -backend=false && terraform -chdir=envs/production validate
```

**Bootstrap.** CI checks changes under `bootstrap/` but never applies them. Apply them from
your machine as in step 1, using the saved state file.

**Application secrets.** To add one, add an entry to `app_secrets` in
`envs/production/terraform.tfvars` (environment variable name to secret short name), apply,
then set its value as in step 7. It reaches the containers on the next release.

**Provider versions.** The AWS provider is constrained to `~> 6.4` and locked at 6.73.0 in each
configuration's `.terraform.lock.hcl`. Commit the lock files; `.terraform/` is ignored.

## Tearing it down

`terraform destroy` is never run by CI; run it from your machine with administrator
credentials for the account. Destroy production first, then bootstrap, because the bootstrap
bucket holds production's state.

**This permanently deletes the database, every uploaded file, all container images and all
logs.** The only thing kept is one final database snapshot.

### 1. Destroy production

A plain `terraform destroy` fails by design: the load balancer and database have deletion
protection, and the uploads bucket and ECR repositories refuse to be deleted while they hold
data. The `allow_destroy` variable lifts all four guards, and has to be applied before the
destroy so the change reaches the resources.

Stop releases and infrastructure merges first, so CI is not deploying while you destroy.

```bash
cd envs/production
```

```bash
terraform init
```

Lift the guards. This is an in-place change to the load balancer, database, bucket and
repositories; nothing is deleted yet.

```bash
terraform apply -var allow_destroy=true
```

Destroy. Review the plan Terraform shows before confirming; it takes around 15 minutes.

```bash
terraform destroy -var allow_destroy=true
```

Passing the variable on the command line keeps `allow_destroy` out of `terraform.tfvars`, so
it can't be left switched on by accident.

### 2. Clean up what Terraform leaves behind

| Left behind | Why | What to do |
| --- | --- | --- |
| Database snapshot `billing-dashboard-final` | Taken automatically as a last backup | Keep it as long as you might need the data, then delete it in the RDS console. It must be deleted before the stack can be destroyed a second time, because the name is reused. |
| Application secrets, such as `billing-dashboard/app-key` | Secrets Manager holds deleted secrets for 7 days | Nothing, unless you are rebuilding within 7 days; the names are reserved until then. To free a name immediately, run the command below. |
| ACM certificate | Created by hand, not by Terraform | Delete it in the ACM console. |
| DNS records in the DNS account | Managed in another AWS account | Ask its owner to remove the dashboard record and the certificate validation CNAME. |
| GitHub variables and `production` environments | Not managed by Terraform | Remove `AWS_BUILD_ROLE_ARN` and `AWS_DEPLOY_ROLE_ARN` from the application repository; the roles they point to no longer exist. |

```bash
aws secretsmanager delete-secret --region eu-west-1 --secret-id billing-dashboard/app-key --force-delete-without-recovery
```

### 3. Destroy bootstrap (optional)

Only do this if the account is being retired from this project altogether. It removes the
state bucket and the two roles the infrastructure workflow uses, so CI stops working. The
account's GitHub OIDC provider is not touched; bootstrap only looks it up.

The state bucket is protected twice: `prevent_destroy` in the code, and S3 refusing to delete
a bucket that still contains objects.

1. In `bootstrap/main.tf`, remove the `lifecycle { prevent_destroy = true }` block from
   `aws_s3_bucket.state`.
2. Empty the bucket, including old versions: in the S3 console, select
   `raventrack-billing-dashboard-tfstate` and choose **Empty**.
3. Destroy:

```bash
cd bootstrap
```

```bash
terraform destroy
```

Afterwards, remove `AWS_TERRAFORM_PLAN_ROLE_ARN` and `AWS_TERRAFORM_APPLY_ROLE_ARN` from this
repository's variables, and delete the local `bootstrap/terraform.tfstate` files.

## GitHub Actions reference

Both workflows authenticate through GitHub OIDC, so no AWS keys are stored in GitHub.

**`.github/workflows/infra.yml`** (this repository)

| Trigger | What runs | Role variable |
| --- | --- | --- |
| Pull request | fmt check, validate, plan, plan posted as a PR comment | `AWS_TERRAFORM_PLAN_ROLE_ARN` |
| Merge to main | plan and apply to production, after environment approval | `AWS_TERRAFORM_APPLY_ROLE_ARN` |

**`app-workflows/deploy.yml`** (runs in the application repository)

1. **Test.** Pint, PHPStan and the test suite against a PostgreSQL service container.
2. **Build and push.** App and nginx images tagged with the commit SHA, using
   `AWS_BUILD_ROLE_ARN`. Skipped when the images already exist, since tags are immutable.
3. **Approve.** One approval on the `production` environment covers the rest.
4. **Migrate.** Registers a new worker task definition revision and runs
   `php artisan migrate --force`, then `php artisan app:setup-production`, as a one-off task;
   a non-zero exit code stops the release. Both run on every release, so the setup command
   must be idempotent and compatible with the code still serving traffic.
5. **Deploy web.** ECS runs the blue/green stages. The job then checks the service is running
   the new revision, so a rollback fails the release.
6. **Deploy worker and scheduler.** Rolling, after web traffic has shifted.

Steps 4 to 6 use `AWS_DEPLOY_ROLE_ARN`.

## Design notes

- **Certificate and DNS are external.** The `alb` module takes `certificate_arn` and creates
  no ACM or Route 53 resources. The `alb_dns` output has what the DNS account needs.
- **Two GitHub roles for the application repository.** `github-build` pushes images from
  `main` before the approval gate; `github-deploy` migrates and deploys, and is assumable only
  from the `production` GitHub Environment. `app-workflows/iam/` holds the same policies as
  JSON for reference; Terraform creates the real roles, so do not also create them by hand.
- **Blue/green toggle.** `enable_blue_green = false` deploys web with the rolling strategy;
  `true` uses ECS native blue/green.
- **Database password.** RDS generates and stores it in Secrets Manager; tasks read it from
  there as `DB_PASSWORD`. The app connects as the master user.
- **Migrations.** CI runs the one-off migration task from the worker task definition (see the
  `migration_task` output), because the web task would keep running behind nginx.
- **Scheduler.** Deploys stop the old task before starting the new one, so it never runs twice.
- **Test listener.** Port 8443 is closed unless `test_listener_allowed_cidrs` is set.
- **Alerts.** Alarms publish to an SNS topic; set `alert_email` to subscribe an address.

## Who owns what

- **Terraform** owns the infrastructure and the *initial* task definition revisions.
- **CI** registers a new task definition revision per release and updates the services.
  The services ignore `task_definition` (and web ignores `desired_count`), and the listener
  rules ignore `action`, so `terraform apply` never reverts a release or a traffic shift.
- A Terraform change to a task definition (a new environment variable, CPU, memory) creates
  a new revision that the running service does not pick up by itself. It takes effect on the
  next release, because the release workflow starts from the latest revision of each family.

## Not included

- The ACM certificate and the dashboard's DNS record (see steps 3 and 6).
- WAF.
- Lambda lifecycle hooks for smoke tests against the test listener.
- Queue health alarms: the app publishes those metrics, so the alarms depend on the metric
  names it chooses. The task role may publish to the `metrics_namespace` namespace.
