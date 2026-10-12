provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

module "https_alb" {
  source = "../.."

  name                      = var.name
  vpc_id                    = var.vpc_id
  subnet_ids                = var.subnet_ids
  foundry_source_cidrs      = var.foundry_source_cidrs
  certificate_arn           = var.certificate_arn
  internal                  = var.internal
  backend_protocol          = var.backend_protocol
  backend_port              = var.backend_port
  health_check_path         = var.health_check_path
  target_ips                = var.target_ips
  enable_outbound_client    = var.enable_outbound_client
  foundry_destination_cidrs = var.foundry_destination_cidrs
  access_log_bucket         = var.access_log_bucket
  access_log_prefix         = var.access_log_prefix
  deletion_protection       = var.deletion_protection
  tags                      = var.tags
}
