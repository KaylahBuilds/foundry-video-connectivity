data "aws_subnet" "selected" {
  for_each = var.subnet_ids
  id       = each.value
}

# Standalone rules avoid inline-rule conflicts. The provider removes AWS's
# default allow-all egress when creating these new security groups.
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "HTTPS from verified Foundry client source ranges"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "backend" {
  name_prefix = "${var.name}-backend-"
  description = "Backend and health checks from this ALB only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-backend" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each          = var.foundry_source_cidrs
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from verified Foundry source"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  tags              = var.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_backend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Application and health checks to backend SG"
  referenced_security_group_id = aws_security_group.backend.id
  ip_protocol                  = "tcp"
  from_port                    = var.backend_port
  to_port                      = var.backend_port
  tags                         = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id            = aws_security_group.backend.id
  description                  = "Application and health checks from ALB SG"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.backend_port
  to_port                      = var.backend_port
  tags                         = var.tags
}

# These groups are deliberately independent. An AWS client's HTTPS connection
# to Foundry is not the reverse of the ALB listener or backend permission.
resource "aws_security_group" "outbound_client" {
  count       = var.enable_outbound_client ? 1 : 0
  name_prefix = "${var.name}-client-"
  description = "AWS client HTTPS to verified Foundry destinations"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-client" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "client_to_foundry" {
  for_each          = var.enable_outbound_client ? var.foundry_destination_cidrs : toset([])
  security_group_id = aws_security_group.outbound_client[0].id
  description       = "HTTPS to verified Foundry destination"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  tags              = var.tags
}

resource "aws_lb" "video" {
  name                       = "${var.name}-alb"
  internal                   = var.internal
  load_balancer_type         = "application"
  ip_address_type            = "ipv4"
  subnets                    = var.subnet_ids
  security_groups            = [aws_security_group.alb.id]
  enable_deletion_protection = var.deletion_protection
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "strictest"
  tags                       = var.tags

  dynamic "access_logs" {
    for_each = var.access_log_bucket == null ? [] : [var.access_log_bucket]
    content {
      enabled = true
      bucket  = access_logs.value
      prefix  = var.access_log_prefix
    }
  }

  lifecycle {
    precondition {
      condition     = alltrue([for subnet in data.aws_subnet.selected : subnet.vpc_id == var.vpc_id])
      error_message = "Every ALB subnet must belong to vpc_id."
    }
    precondition {
      condition     = length(toset([for subnet in data.aws_subnet.selected : subnet.availability_zone])) == length(var.subnet_ids)
      error_message = "ALB requires distinct Availability Zones: select exactly one subnet per zone."
    }
  }
}

resource "aws_lb_target_group" "video" {
  # A protocol/port change replaces the target group. A generated suffix lets
  # Terraform create the replacement before switching the listener to it.
  name_prefix          = "${substr(var.name, 0, 5)}-"
  target_type          = "ip"
  ip_address_type      = "ipv4"
  vpc_id               = var.vpc_id
  protocol             = var.backend_protocol
  protocol_version     = "HTTP1"
  port                 = var.backend_port
  deregistration_delay = 300
  tags                 = var.tags

  health_check {
    enabled             = true
    protocol            = var.backend_protocol
    port                = "traffic-port"
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.video.arn
  protocol          = "HTTPS"
  port              = 443
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  tags              = var.tags

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.video.arn
  }
}

resource "aws_lb_target_group_attachment" "video" {
  for_each         = var.target_ips
  target_group_arn = aws_lb_target_group.video.arn
  target_id        = each.value
  port             = var.backend_port
}
