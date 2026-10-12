output "alb_arn" {
  description = "Application Load Balancer ARN."
  value       = aws_lb.video.arn
}

output "alb_dns_name" {
  description = "AWS ALB DNS name, not necessarily covered by the supplied certificate. Publish a matching owned hostname separately."
  value       = aws_lb.video.dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted-zone ID for an optional Route 53 alias managed elsewhere."
  value       = aws_lb.video.zone_id
}

output "listener_arn" {
  description = "HTTPS-only listener ARN. No port-80 listener is created."
  value       = aws_lb_listener.https.arn
}

output "target_group_arn" {
  description = "IP target group ARN. Workload infrastructure may register targets instead of target_ips."
  value       = aws_lb_target_group.video.arn
}

output "alb_security_group_id" {
  description = "Security group attached to this ALB."
  value       = aws_security_group.alb.id
}

output "backend_security_group_id" {
  description = "Attach to target ENIs through their owning workload infrastructure. Other attached groups may broaden permissions."
  value       = aws_security_group.backend.id
}

output "outbound_client_security_group_id" {
  description = "Optional AWS HTTPS-client SG to attach through workload infrastructure; null when disabled."
  value       = try(aws_security_group.outbound_client[0].id, null)
}
