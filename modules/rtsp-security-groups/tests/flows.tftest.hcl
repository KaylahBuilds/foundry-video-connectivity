# All runs use Terraform's mock provider. No credentials or AWS resources.
mock_provider "aws" {}

run "reject_reserved_security_group_name" {
  command = plan
  variables { name = "sg-video" }
  expect_failures = [var.name]
}

variables {
  name            = "rtsp-test"
  vpc_id          = "vpc-0123456789abcdef0"
  aws_role        = "server"
  transport       = "tcp"
  peer_ipv4_cidrs = ["192.0.2.10/32"]
}

run "tcp_server_only_control_ingress" {
  command = plan

  assert {
    condition = length(aws_vpc_security_group_ingress_rule.flow) == 1 && length(aws_vpc_security_group_egress_rule.flow) == 0 && alltrue([
      for rule in aws_vpc_security_group_ingress_rule.flow : rule.ip_protocol == "tcp" && rule.from_port == 554 && rule.to_port == 554 && rule.cidr_ipv4 == "192.0.2.10/32"
    ])
    error_message = "A TCP server must admit only the specified peer's RTSP connection, without UDP or unsolicited outbound rules."
  }
}

run "tcp_client_only_control_egress" {
  command = plan

  variables {
    aws_role = "client"
  }

  assert {
    condition = length(aws_vpc_security_group_ingress_rule.flow) == 0 && length(aws_vpc_security_group_egress_rule.flow) == 1 && alltrue([
      for rule in aws_vpc_security_group_egress_rule.flow : rule.ip_protocol == "tcp" && rule.from_port == 554 && rule.to_port == 554 && rule.cidr_ipv4 == "192.0.2.10/32"
    ])
    error_message = "A TCP client needs only the remote server destination port; no UDP or unsolicited inbound rule."
  }
}

run "udp_server_explicit_media_and_feedback" {
  command = plan

  variables {
    transport = "udp"
  }

  assert {
    condition = length(aws_vpc_security_group_ingress_rule.flow) == 2 && length(aws_vpc_security_group_egress_rule.flow) == 2 && alltrue([
      for rule in aws_vpc_security_group_ingress_rule.flow : rule.cidr_ipv4 == "192.0.2.10/32" && rule.from_port == rule.to_port && ((rule.ip_protocol == "tcp" && rule.from_port == 554) || (rule.ip_protocol == "udp" && rule.from_port == 6001))
      ]) && alltrue([
      for rule in aws_vpc_security_group_egress_rule.flow : rule.cidr_ipv4 == "192.0.2.10/32" && rule.ip_protocol == "udp" && rule.from_port == rule.to_port && contains([5004, 5005], rule.from_port)
    ])
    error_message = "The server receives TCP control and UDP feedback, then sends RTP and RTCP to the client's destination ports."
  }
}

run "udp_client_explicit_media_and_feedback" {
  command = plan

  variables {
    aws_role  = "client"
    transport = "udp"
  }

  assert {
    condition = length(aws_vpc_security_group_ingress_rule.flow) == 2 && length(aws_vpc_security_group_egress_rule.flow) == 2 && alltrue([
      for rule in aws_vpc_security_group_ingress_rule.flow : rule.cidr_ipv4 == "192.0.2.10/32" && rule.ip_protocol == "udp" && rule.from_port == rule.to_port && contains([5004, 5005], rule.from_port)
      ]) && alltrue([
      for rule in aws_vpc_security_group_egress_rule.flow : rule.cidr_ipv4 == "192.0.2.10/32" && rule.from_port == rule.to_port && ((rule.ip_protocol == "tcp" && rule.from_port == 554) || (rule.ip_protocol == "udp" && rule.from_port == 6001))
    ])
    error_message = "The client initiates control and feedback while receiving media at its local destination ports."
  }
}

run "custom_ports_and_multiple_peers" {
  command = plan

  variables {
    transport         = "udp"
    peer_ipv4_cidrs   = ["192.0.2.10/32", "198.51.100.0/24"]
    rtsp_port         = 8554
    client_rtp_ports  = { from = 10000, to = 10031 }
    client_rtcp_ports = { from = 12000, to = 12000 }
    server_rtcp_ports = { from = 14000, to = 14001 }
  }

  assert {
    condition = length(aws_vpc_security_group_ingress_rule.flow) == 4 && length(aws_vpc_security_group_egress_rule.flow) == 4 && alltrue([
      for rule in aws_vpc_security_group_ingress_rule.flow : (rule.ip_protocol == "tcp" && rule.from_port == 8554 && rule.to_port == 8554) || (rule.ip_protocol == "udp" && rule.from_port == 14000 && rule.to_port == 14001)
      ]) && alltrue([
      for rule in aws_vpc_security_group_egress_rule.flow : rule.ip_protocol == "udp" && ((rule.from_port == 10000 && rule.to_port == 10031) || (rule.from_port == 12000 && rule.to_port == 12000))
    ])
    error_message = "Both explicit peers must receive only configured destination ranges."
  }
}

run "multiplexed_receiver_port_deduplicated" {
  command = plan

  variables {
    transport         = "udp"
    client_rtcp_ports = { from = 5004, to = 5004 }
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.flow) == 1 && length(aws_vpc_security_group_ingress_rule.flow) == 2
    error_message = "Identical RTP/RTCP receiver ports must not create duplicate AWS rules. Negotiation is still external."
  }
}

run "valid_port_edges" {
  command = plan

  variables {
    transport         = "udp"
    rtsp_port         = 65535
    client_rtp_ports  = { from = 1, to = 1 }
    client_rtcp_ports = { from = 65535, to = 65535 }
    server_rtcp_ports = { from = 65504, to = 65535 }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.flow) == 2 && length(aws_vpc_security_group_egress_rule.flow) == 2
    error_message = "Valid inclusive port boundaries and a 32-port range should be accepted."
  }
}

run "reject_world_open_peer" {
  command = plan
  variables {
    peer_ipv4_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.peer_ipv4_cidrs]
}

run "reject_ipv6_peer" {
  command = plan
  variables {
    peer_ipv4_cidrs = ["2001:db8::/32"]
  }
  expect_failures = [var.peer_ipv4_cidrs]
}

run "reject_empty_peers" {
  command = plan
  variables {
    peer_ipv4_cidrs = []
  }
  expect_failures = [var.peer_ipv4_cidrs]
}

run "reject_noncanonical_peer" {
  command = plan
  variables {
    peer_ipv4_cidrs = ["192.0.2.10/24"]
  }
  expect_failures = [var.peer_ipv4_cidrs]
}

run "reject_invalid_role" {
  command = plan
  variables {
    aws_role = "both"
  }
  expect_failures = [var.aws_role]
}

run "reject_invalid_transport" {
  command = plan
  variables {
    transport = "all"
  }
  expect_failures = [var.transport]
}

run "reject_zero_control_port" {
  command = plan
  variables {
    rtsp_port = 0
  }
  expect_failures = [var.rtsp_port]
}

run "reject_fractional_control_port" {
  command = plan
  variables {
    rtsp_port = 554.5
  }
  expect_failures = [var.rtsp_port]
}

run "reject_large_control_port" {
  command = plan
  variables {
    rtsp_port = 65536
  }
  expect_failures = [var.rtsp_port]
}

run "reject_rtp_wide_range" {
  command = plan
  variables {
    client_rtp_ports = { from = 1, to = 65535 }
  }
  expect_failures = [var.client_rtp_ports]
}

run "reject_rtp_reversed_range" {
  command = plan
  variables {
    client_rtp_ports = { from = 6000, to = 5000 }
  }
  expect_failures = [var.client_rtp_ports]
}

run "reject_client_rtcp_fraction" {
  command = plan
  variables {
    client_rtcp_ports = { from = 5005.5, to = 5006 }
  }
  expect_failures = [var.client_rtcp_ports]
}

run "reject_client_rtcp_33_ports" {
  command = plan
  variables {
    client_rtcp_ports = { from = 5000, to = 5032 }
  }
  expect_failures = [var.client_rtcp_ports]
}

run "reject_server_rtcp_out_of_range" {
  command = plan
  variables {
    server_rtcp_ports = { from = 65535, to = 65536 }
  }
  expect_failures = [var.server_rtcp_ports]
}

run "reject_server_rtcp_zero" {
  command = plan
  variables {
    server_rtcp_ports = { from = 0, to = 1 }
  }
  expect_failures = [var.server_rtcp_ports]
}
