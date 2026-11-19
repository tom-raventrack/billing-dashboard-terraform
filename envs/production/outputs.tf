# Values the release workflow (deploy.yml) needs.

output "url" {
  value = "https://${var.domain_name}"
}

output "alb_dns" {
  description = "Create the dashboard's record in the DNS account from this: a CNAME to dns_name, or a Route 53 alias A record using dns_name and zone_id."
  value = {
    record   = var.domain_name
    dns_name = module.alb.dns_name
    zone_id  = module.alb.zone_id
  }
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "github_build_role_arn" {
  description = "Assumed by the build job to push images."
  value       = module.iam.github_build_role_arn
}

output "github_deploy_role_arn" {
  description = "Assumed by the migrate and deploy jobs in the production environment."
  value       = module.iam.github_deploy_role_arn
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "ecs_service_names" {
  value = {
    web       = module.web.service_name
    worker    = module.worker.service_name
    scheduler = module.scheduler.service_name
  }
}

output "task_definition_families" {
  value = {
    web       = module.web.task_definition_family
    worker    = module.worker.task_definition_family
    scheduler = module.scheduler.task_definition_family
  }
}

output "migration_task" {
  description = "Run the one-off `php artisan migrate --force` task with the worker task definition (single container, so the task exits when the command does), overriding the app container's command."
  value = {
    task_definition_family = module.worker.task_definition_family
    container_name         = "app"
    subnet_ids             = module.network.private_subnet_ids
    security_group_ids     = [module.ecs_cluster.task_security_group_id]
  }
}

output "app_secret_arns" {
  description = "Secrets whose values must be set outside Terraform before tasks can start."
  value       = module.data.secret_arns
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "ses_dkim_records" {
  description = "CNAMEs that verify the SES sending domain. Add them in the DNS account; SES cannot send until the domain is verified."
  value       = module.mail.dkim_records
}
