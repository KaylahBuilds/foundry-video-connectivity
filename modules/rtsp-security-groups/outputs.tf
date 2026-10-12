output "security_group_id" {
  description = "Associate this new SG through the infrastructure owning the AWS client/server interfaces. Association is not automated."
  value       = aws_security_group.rtsp.id
}

output "ingress_rules" {
  description = "Planned inbound protocol, peer source CIDR, and AWS destination ports."
  value = [for rule in aws_vpc_security_group_ingress_rule.flow : {
    protocol = rule.ip_protocol
    cidr     = rule.cidr_ipv4
    from     = rule.from_port
    to       = rule.to_port
  }]
}

output "egress_rules" {
  description = "Planned outbound protocol, peer destination CIDR, and remote destination ports."
  value = [for rule in aws_vpc_security_group_egress_rule.flow : {
    protocol = rule.ip_protocol
    cidr     = rule.cidr_ipv4
    from     = rule.from_port
    to       = rule.to_port
  }]
}
