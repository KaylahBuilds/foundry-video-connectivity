locals {
  flows = concat([
    {
      ingress     = var.aws_role == "server"
      protocol    = "tcp"
      from        = var.rtsp_port
      to          = var.rtsp_port
      description = "RTSP server destination port; interleaved media shares TCP if configured"
    }
    ], var.transport == "udp" ? [
    {
      ingress     = var.aws_role == "client"
      protocol    = "udp"
      from        = var.client_rtp_ports.from
      to          = var.client_rtp_ports.to
      description = "RTP client receive destination ports"
    },
    {
      ingress     = var.aws_role == "client"
      protocol    = "udp"
      from        = var.client_rtcp_ports.from
      to          = var.client_rtcp_ports.to
      description = "RTCP client receive destination ports"
    },
    {
      ingress     = var.aws_role == "server"
      protocol    = "udp"
      from        = var.server_rtcp_ports.from
      to          = var.server_rtcp_ports.to
      description = "RTCP server feedback receive destination ports"
    }
  ] : [])

  # Group exact duplicates: negotiated RTP/RTCP multiplexing can share a port.
  # This only avoids duplicate SG rules; it does not configure multiplexing.
  rules = flatten([
    for flow in local.flows : [
      for cidr in var.peer_ipv4_cidrs : merge(flow, { cidr = cidr })
    ]
  ])
  ingress_rules = {
    for rule in local.rules : "${rule.protocol}:${rule.from}:${rule.to}:${rule.cidr}" => rule... if rule.ingress
  }
  egress_rules = {
    for rule in local.rules : "${rule.protocol}:${rule.from}:${rule.to}:${rule.cidr}" => rule... if !rule.ingress
  }
}

resource "aws_security_group" "rtsp" {
  name_prefix            = "${var.name}-"
  description            = "Explicit ${var.aws_role} RTSP ${var.transport} flows; existing routed connection required"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  # The provider removes AWS's initial allow-all egress rule on creation.
  # Rules are managed only by the standalone resources below.
  tags = merge(var.tags, {
    Name      = var.name
    ManagedBy = "Terraform"
    Role      = var.aws_role
    Transport = var.transport
  })
}

resource "aws_vpc_security_group_ingress_rule" "flow" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.rtsp.id
  cidr_ipv4         = each.value[0].cidr
  ip_protocol       = each.value[0].protocol
  from_port         = each.value[0].from
  to_port           = each.value[0].to
  description       = join("; ", [for rule in each.value : rule.description])
}

resource "aws_vpc_security_group_egress_rule" "flow" {
  for_each = local.egress_rules

  security_group_id = aws_security_group.rtsp.id
  cidr_ipv4         = each.value[0].cidr
  ip_protocol       = each.value[0].protocol
  from_port         = each.value[0].from
  to_port           = each.value[0].to
  description       = join("; ", [for rule in each.value : rule.description])
}
