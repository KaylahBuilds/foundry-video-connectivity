output "security_group_id" {
  description = "New group ID for association by the interface owner's infrastructure."
  value       = module.rtsp.security_group_id
}

output "ingress_rules" {
  description = "Inbound peer source CIDRs and AWS destination ports."
  value       = module.rtsp.ingress_rules
}

output "egress_rules" {
  description = "Outbound peer destination CIDRs and remote destination ports."
  value       = module.rtsp.egress_rules
}
