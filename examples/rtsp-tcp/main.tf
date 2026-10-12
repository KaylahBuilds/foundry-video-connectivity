provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

module "rtsp" {
  source = "../../modules/rtsp-security-groups"

  name            = var.name
  vpc_id          = var.vpc_id
  aws_role        = var.aws_role
  transport       = "tcp"
  peer_ipv4_cidrs = var.peer_ipv4_cidrs
  rtsp_port       = var.rtsp_port
  tags            = var.tags
}
