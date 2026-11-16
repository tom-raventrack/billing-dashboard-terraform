output "security_group_id" {
  value = aws_security_group.alb.id
}

output "dns_name" {
  description = "Target for the dashboard's DNS record in the DNS account."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "ALB hosted zone ID, needed if the DNS record is a Route 53 alias."
  value       = aws_lb.this.zone_id
}

output "arn_suffix" {
  description = "Load balancer dimension value for CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "blue_target_group_arn" {
  value = aws_lb_target_group.web["blue"].arn
}

output "green_target_group_arn" {
  value = aws_lb_target_group.web["green"].arn
}

output "target_group_arn_suffixes" {
  description = "Map of blue/green to the TargetGroup dimension value for CloudWatch metrics."
  value       = { for k, tg in aws_lb_target_group.web : k => tg.arn_suffix }
}

output "production_listener_rule_arn" {
  value = aws_lb_listener_rule.production.arn
}

output "test_listener_rule_arn" {
  value = aws_lb_listener_rule.test.arn
}
