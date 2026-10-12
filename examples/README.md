# Choose the transport and AWS role

The examples are alternatives. They reuse existing networks and do not configure a Foundry connector. Verify connector support before creating resources.

| Your confirmed integration | Start here | AWS role |
| --- | --- | --- |
| Foundry-compatible client requests HTTPS from an AWS application | [https-alb](https-alb) | Server behind ALB |
| Compatible client pulls a stream from an AWS RTSP server using interleaved TCP | [rtsp-tcp](rtsp-tcp), `aws_role = "server"` | Server |
| AWS pulls from a remote RTSP server using interleaved TCP | [rtsp-tcp](rtsp-tcp), `aws_role = "client"` | Client |
| Compatible client pulls from AWS with separate UDP media | [rtsp-udp](rtsp-udp), `aws_role = "server"` | Server |
| AWS pulls from a remote server with separate UDP media | [rtsp-udp](rtsp-udp), `aws_role = "client"` | Client |

The remote server in the last two client examples is not necessarily Foundry. Do not assume Foundry exposes an RTSP server. These are pull-session patterns; a push workflow needs its own protocol review.

## Read the UDP rules by destination

For the illustrative separate-media session:

| Flow | AWS server | AWS client | Destination port |
| --- | --- | --- | --- |
| Client opens RTSP control | Ingress | Egress | Server TCP 554 |
| Server sends RTP | Egress | Ingress | Client UDP 5004 |
| Server sends RTCP | Egress | Ingress | Client UDP 5005 |
| Client sends RTCP feedback | Ingress | Egress | Server UDP 6001 |

Ingress ports belong to the AWS endpoint. Egress ports belong to its remote peer. The same TCP control connection's response traffic is statefully tracked; a separate UDP flow needs its own permissions. The examples describe distinct RTP/RTCP sockets. They do not automatically infer negotiated ports, support multicast, or adapt to arbitrary RTCP multiplexing.

Use explicit remote IPv4 peer CIDRs and actual application settings. NAT can change the addresses or ports observed on the path. A rule which looks correct for the advertised address can still fail at the real receiver.

The reusable RTSP module limits an individual UDP range to 32 destination ports as a lab guardrail. That is a project choice, not an AWS or RTP limit. If your workload needs more, review the port allocator, session count, routing, security policy and tests before changing it.

## Deploy one example at a time

Each example is an independent Terraform root with its own state. Never apply the reusable modules directly with credentials. Never manage an existing security group or ALB by pointing these examples at its identifier: they create new resources and expose their IDs for integration.

Initialization, formatting, validation and mock tests do not create cloud infrastructure. `plan` reads your AWS account; `apply` creates or changes resources. No commands in CI perform a real apply.
