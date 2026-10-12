provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

module "rtsp" {
  source = "../../modules/rtsp-security-groups"

  name              = var.name
  vpc_id            = var.vpc_id
  aws_role          = var.aws_role
  transport         = "udp"
  peer_ipv4_cidrs   = var.peer_ipv4_cidrs
  rtsp_port         = var.rtsp_port
  client_rtp_ports  = var.client_rtp_ports
  client_rtcp_ports = var.client_rtcp_ports
  server_rtcp_ports = var.server_rtcp_ports
  tags              = var.tags
}
