mock_provider "aws" {
  # Use syntactically valid IDs/ARNs because downstream resources consume
  # these computed attributes even though no AWS API calls are performed.
  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/foundry-video-alb/1234567890abcdef"
      dns_name = "internal-foundry-video-alb-1234567890.us-east-1.elb.amazonaws.com"
      zone_id  = "Z35SXDOTRQ7X7K"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/foundry-targets/1234567890abcdef"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef3"
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      vpc_id            = "vpc-0123456789abcdef0"
      availability_zone = "us-east-1a"
    }
  }
}

override_data {
  target = data.aws_subnet.selected["subnet-0123456789abcdef2"]
  values = {
    vpc_id            = "vpc-0123456789abcdef0"
    availability_zone = "us-east-1b"
  }
}

override_resource {
  target = aws_security_group.alb
  values = { id = "sg-0123456789abcdef1" }
}

override_resource {
  target = aws_security_group.backend
  values = { id = "sg-0123456789abcdef2" }
}

variables {
  name                 = "foundry-video"
  vpc_id               = "vpc-0123456789abcdef0"
  subnet_ids           = ["subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]
  foundry_source_cidrs = ["192.0.2.10/32"]
  certificate_arn      = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}

# Mock apply exercises computed references without contacting AWS. No real
# provider credentials, real resource application, or integration proof.
run "private_https_defaults" {
  command = apply

  assert {
    condition     = aws_lb.video.internal && aws_lb.video.load_balancer_type == "application" && aws_lb.video.ip_address_type == "ipv4"
    error_message = "The ALB must default to internal IPv4 application mode."
  }
  assert {
    condition     = aws_lb.video.enable_deletion_protection && aws_lb.video.drop_invalid_header_fields && aws_lb.video.desync_mitigation_mode == "strictest"
    error_message = "Deletion protection and header/request hardening must remain enabled."
  }
  assert {
    condition     = aws_lb_listener.https.port == 443 && aws_lb_listener.https.protocol == "HTTPS" && aws_lb_listener.https.ssl_policy == "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
    error_message = "Only HTTPS with the explicit TLS 1.2/1.3 policy is intended."
  }
  assert {
    condition     = aws_lb_target_group.video.target_type == "ip" && aws_lb_target_group.video.protocol == "HTTP" && aws_lb_target_group.video.port == 8080
    error_message = "The default backend must be an HTTP/8080 IP target group."
  }
  assert {
    condition     = aws_lb_target_group.video.health_check[0].port == "traffic-port" && aws_lb_target_group.video.health_check[0].protocol == "HTTP" && aws_lb_target_group.video.health_check[0].path == "/health" && aws_lb_target_group.video.health_check[0].matcher == "200"
    error_message = "Health checks must use the allowed backend port and exact success status."
  }
  assert {
    condition     = length(aws_lb_target_group_attachment.video) == 0 && length(aws_security_group.outbound_client) == 0 && length(aws_vpc_security_group_egress_rule.client_to_foundry) == 0 && output.outbound_client_security_group_id == null
    error_message = "Targets and AWS-client outbound access must remain opt-in."
  }
  assert {
    condition     = length(aws_lb.video.access_logs) == 0
    error_message = "Logging must not reference an invented bucket."
  }
}

run "security_group_boundaries" {
  command = apply

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.https : rule.cidr_ipv4 == "192.0.2.10/32" && rule.ip_protocol == "tcp" && rule.from_port == 443 && rule.to_port == 443 && rule.security_group_id == aws_security_group.alb.id
    ])
    error_message = "Only the supplied source on TCP 443 may enter the ALB."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.alb_to_backend.security_group_id == aws_security_group.alb.id && aws_vpc_security_group_egress_rule.alb_to_backend.referenced_security_group_id == aws_security_group.backend.id && aws_vpc_security_group_egress_rule.alb_to_backend.ip_protocol == "tcp" && aws_vpc_security_group_egress_rule.alb_to_backend.from_port == 8080 && aws_vpc_security_group_egress_rule.alb_to_backend.to_port == 8080
    error_message = "ALB egress must target the backend SG on the single backend port."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.backend_from_alb.security_group_id == aws_security_group.backend.id && aws_vpc_security_group_ingress_rule.backend_from_alb.referenced_security_group_id == aws_security_group.alb.id && aws_vpc_security_group_ingress_rule.backend_from_alb.ip_protocol == "tcp" && aws_vpc_security_group_ingress_rule.backend_from_alb.from_port == 8080 && aws_vpc_security_group_ingress_rule.backend_from_alb.to_port == 8080
    error_message = "The backend must trust only this ALB SG on its application port."
  }
}

run "https_backend_and_explicit_targets" {
  command = apply

  variables {
    backend_protocol = "HTTPS"
    backend_port     = 8443
    target_ips       = { video_a = "10.20.1.10", video_b = "10.20.2.10" }
  }

  assert {
    condition     = aws_lb_target_group.video.protocol == "HTTPS" && aws_lb_target_group.video.health_check[0].protocol == "HTTPS" && aws_lb_target_group.video.port == 8443
    error_message = "HTTPS target traffic and checks must use the configured backend transport."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.alb_to_backend.from_port == 8443 && aws_vpc_security_group_egress_rule.alb_to_backend.to_port == 8443 && aws_vpc_security_group_ingress_rule.backend_from_alb.from_port == 8443 && aws_vpc_security_group_ingress_rule.backend_from_alb.to_port == 8443
    error_message = "Both SG rules must move with the backend port."
  }
  assert {
    condition     = length(aws_lb_target_group_attachment.video) == 2 && aws_lb_target_group_attachment.video["video_a"].target_id == "10.20.1.10" && alltrue([for target in aws_lb_target_group_attachment.video : target.port == 8443])
    error_message = "Explicit IP attachments must retain their stable identities and backend port."
  }
}

run "explicit_optional_features" {
  command = apply

  variables {
    internal                  = false
    deletion_protection       = false
    enable_outbound_client    = true
    foundry_destination_cidrs = ["198.51.100.20/32", "198.51.100.21/32"]
    access_log_bucket         = "example-existing-alb-log-bucket"
    access_log_prefix         = "foundry/access"
  }

  assert {
    condition     = !aws_lb.video.internal && !aws_lb.video.enable_deletion_protection && length(aws_security_group.outbound_client) == 1 && length(aws_vpc_security_group_egress_rule.client_to_foundry) == 2
    error_message = "Explicit opt-ins must control public exposure and the optional client group."
  }
  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_egress_rule.client_to_foundry : rule.ip_protocol == "tcp" && rule.from_port == 443 && rule.to_port == 443 && contains(var.foundry_destination_cidrs, rule.cidr_ipv4)
    ])
    error_message = "Client egress must be limited to configured destinations on HTTPS."
  }
  assert {
    condition     = aws_lb.video.access_logs[0].enabled && aws_lb.video.access_logs[0].bucket == "example-existing-alb-log-bucket" && aws_lb.video.access_logs[0].prefix == "foundry/access"
    error_message = "Access logs must use only the supplied bucket and prefix."
  }
}

run "reject_world_ingress" {
  command = plan
  variables { foundry_source_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.foundry_source_cidrs]
}

run "reject_empty_ingress" {
  command = plan
  variables { foundry_source_cidrs = [] }
  expect_failures = [var.foundry_source_cidrs]
}

run "reject_ipv6_in_ipv4_example" {
  command = plan
  variables { foundry_source_cidrs = ["2001:db8::/64"] }
  expect_failures = [var.foundry_source_cidrs]
}

run "reject_malformed_cidr" {
  command = plan
  variables { foundry_source_cidrs = ["not-a-cidr"] }
  expect_failures = [var.foundry_source_cidrs]
}

run "reject_source_cidr_host_bits" {
  command = plan
  variables { foundry_source_cidrs = ["192.0.2.10/24"] }
  expect_failures = [var.foundry_source_cidrs]
}

run "reject_one_subnet" {
  command = plan
  variables { subnet_ids = ["subnet-0123456789abcdef1"] }
  expect_failures = [var.subnet_ids]
}

run "reject_subnets_in_one_zone" {
  command = plan
  override_data {
    target = data.aws_subnet.selected["subnet-0123456789abcdef2"]
    values = {
      vpc_id            = "vpc-0123456789abcdef0"
      availability_zone = "us-east-1a"
    }
  }
  expect_failures = [aws_lb.video]
}

run "reject_subnet_in_wrong_vpc" {
  command = plan
  override_data {
    target = data.aws_subnet.selected["subnet-0123456789abcdef2"]
    values = {
      vpc_id            = "vpc-0123456789abcdef9"
      availability_zone = "us-east-1b"
    }
  }
  expect_failures = [aws_lb.video]
}

run "reject_invalid_certificate" {
  command = plan
  variables { certificate_arn = "not-an-acm-certificate" }
  expect_failures = [var.certificate_arn]
}

run "reject_reserved_alb_name" {
  command = plan
  variables { name = "internal-video" }
  expect_failures = [var.name]
}

run "reject_reserved_security_group_name" {
  command = plan
  variables { name = "sg-video" }
  expect_failures = [var.name]
}

run "reject_rtsp_alb_backend" {
  command = plan
  variables { backend_protocol = "TCP" }
  expect_failures = [var.backend_protocol]
}

run "reject_zero_backend_port" {
  command = plan
  variables { backend_port = 0 }
  expect_failures = [var.backend_port]
}

run "reject_fractional_backend_port" {
  command = plan
  variables { backend_port = 8080.5 }
  expect_failures = [var.backend_port]
}

run "reject_out_of_range_backend_port" {
  command = plan
  variables { backend_port = 65536 }
  expect_failures = [var.backend_port]
}

run "reject_public_target" {
  command = plan
  variables { target_ips = { video_a = "8.8.8.8" } }
  expect_failures = [var.target_ips]
}

run "reject_duplicate_targets" {
  command = plan
  variables { target_ips = { video_a = "10.20.1.10", duplicate = "10.20.1.10" } }
  expect_failures = [var.target_ips]
}

run "reject_client_without_destinations" {
  command = plan
  variables { enable_outbound_client = true }
  expect_failures = [var.foundry_destination_cidrs]
}

run "reject_unused_destinations" {
  command = plan
  variables { foundry_destination_cidrs = ["198.51.100.20/32"] }
  expect_failures = [var.foundry_destination_cidrs]
}

run "reject_world_client_egress" {
  command = plan
  variables {
    enable_outbound_client    = true
    foundry_destination_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.foundry_destination_cidrs]
}

run "reject_destination_cidr_host_bits" {
  command = plan
  variables {
    enable_outbound_client    = true
    foundry_destination_cidrs = ["198.51.100.20/24"]
  }
  expect_failures = [var.foundry_destination_cidrs]
}

run "reject_reserved_log_prefix" {
  command = plan
  variables { access_log_prefix = "example/AWSLogs" }
  expect_failures = [var.access_log_prefix]
}

run "reject_invalid_health_path" {
  command = plan
  variables { health_check_path = "health check" }
  expect_failures = [var.health_check_path]
}
