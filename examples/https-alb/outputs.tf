output "alb_dns_name" {
  description = "ALB DNS target, not a substitute for the hostname matching your ACM certificate."
  value       = module.https_alb.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID for a separately managed DNS alias."
  value       = module.https_alb.alb_zone_id
}

output "target_group_arn" {
  description = "Target group for the workload owner to register targets if target_ips is empty."
  value       = module.https_alb.target_group_arn
}

output "backend_security_group_id" {
  description = "Attach through the infrastructure owning the target network interfaces."
  value       = module.https_alb.backend_security_group_id
}

output "outbound_client_security_group_id" {
  description = "Optional client SG; null when disabled."
  value       = module.https_alb.outbound_client_security_group_id
}
