# RTSP security groups: one AWS role, one transport

This module creates one new IPv4 security group for an existing AWS video server **or** client. It does not configure an RTSP application, Foundry connector, load balancer, network interface association, route, VPN, NAT, DNS, or credentials.

Use [the TCP example](../../examples/rtsp-tcp/) for interleaved media or [the UDP example](../../examples/rtsp-udp/) for separate receiver ports. These are alternative configurations of the same module, not instructions to deploy both.

## Choose the role of the AWS interface

| Flow | `aws_role = "server"` | `aws_role = "client"` | Destination port input |
| --- | --- | --- | --- |
| Client opens RTSP control connection | Ingress | Egress | `rtsp_port` (TCP, default 554) |
| Server sends client RTP | Egress | Ingress | `client_rtp_ports` (UDP, default 5004) |
| Server sends client RTCP | Egress | Ingress | `client_rtcp_ports` (UDP, default 5005) |
| Client sends server RTCP feedback | Ingress | Egress | `server_rtcp_ports` (UDP, default 6001) |

Only the first row exists in `transport = "tcp"` mode: configure both applications to interleave media on the RTSP connection. All four rows exist in `transport = "udp"` mode. Do not interpret the server example as a push-stream workflow; these examples model a client pulling from a server.

Every port is a **destination** port. Ingress targets the AWS interface; egress targets the remote peer. The same peer CIDR allowlist applies to all selected flows. If control and media originate from different peers, review and split the design instead of broadening a CIDR indiscriminately.

## Inputs and limits

Required: `name`, `vpc_id`, `aws_role`, `transport`, and `peer_ipv4_cidrs`. The provider is supplied by the caller. Optional inputs are `rtsp_port`, the three UDP `{ from, to }` objects, and `tags`.

- Use 1–20 explicit, canonical IPv4 network CIDRs. Prefer verified `/32` peers. This module rejects `/0`, IPv6, and host bits in network CIDRs; rejecting `/0` does not make every broader allowed CIDR appropriate for your environment.
- Ports are integers from 1 through 65535. Each UDP range contains at most 32 ports, inclusive. This is a deliberate demo guardrail, not a protocol limit.
- UDP ports are independent inputs. The module does not infer RTCP as RTP plus one. Identical receiver ranges are deduplicated to avoid duplicate AWS rules; this does not enable application-level multiplexing.
- No default allow-all egress rule is retained when the provider creates the group. Only the selected flows are added. Return traffic for an established permitted flow is tracked separately by AWS.
- The group is not attached automatically. Add its output ID through the Terraform configuration or controller that owns the interface. Other attached groups can allow more traffic; this group cannot revoke their permissions. See [AWS security group rules](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html).

## Protocol and security boundaries

Confirm the exact connector and both applications support the chosen RTSP version and transport before using these rules. RTSP 2.0 is specified in [RFC 7826](https://www.rfc-editor.org/rfc/rfc7826.html); many deployed devices use RTSP 1.0, so do not assume version compatibility. RTP and RTCP behavior is described in [RFC 3550](https://www.rfc-editor.org/rfc/rfc3550.html).

A TCP control session does not establish a separate UDP media path. Both RTCP directions are explicit in this model instead of relying on an incidental UDP return-flow match. Receiver ports and advertised addresses must agree with the actual application configuration or negotiation.

RTSP and RTP are not encrypted merely because these rules exist. Do not expose plaintext streams or credentials publicly. Use an approved encrypted private path, or independently verified application TLS and SRTP capabilities for control and media as applicable. A private address alone is not encryption, and protecting RTSP control alone does not protect separate RTP media.

No helper embeds credentials in URLs or Terraform variables. Keep authentication in the application or an approved secret manager and redact captures before sharing.

## Outputs and local tests

`security_group_id` is the new group to attach deliberately. `ingress_rules` and `egress_rules` summarize the protocol, peer CIDR, and destination range so reviewers can compare the plan against negotiated traffic.

From this module directory, run:

```sh
terraform init -backend=false
terraform validate
terraform test
```

The tests use a mocked AWS provider and never create AWS resources. Provider installation still requires access to the Terraform registry or an approved provider mirror. Mocked tests verify configuration logic, not AWS reachability, packet delivery, or Foundry compatibility.
