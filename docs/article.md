# Configuring AWS connectivity for Palantir Foundry video streaming with Terraform

Video connectivity is not one firewall rule. A client can reach the RTSP control service and still receive no video, because the media may travel over a different protocol, to a different address, on separately negotiated ports.

This walkthrough separates three designs: HTTPS through an Application Load Balancer, RTSP with media interleaved over TCP, and RTSP with separate RTP and RTCP over UDP. The accompanying Terraform creates AWS networking resources for each design. It does not install a video service, create a Foundry connector or establish that a particular connector supports RTSP.

Start by confirming what your integration actually accepts. The correct network design follows from that answer, not from the word “streaming.”

## Confirm the Foundry integration first

Identify the connector or gateway, where it runs, and whether it supports your protocol, authentication method, codec and media transport. A compatible worker may run inside a private network; another design may use an approved gateway to convert video into a supported representation. Those choices change both the path and the addresses your AWS rules should allow.

Foundry source setup includes network connectivity, egress policy and source credentials. The configuration differs according to the worker architecture. Work with your Foundry administrator on those requirements; generic streaming-data support does not demonstrate support for a raw RTSP feed. [Palantir source setup](https://www.palantir.com/docs/foundry/data-connection/set-up-source)

Use the network examples only after establishing that compatibility. They leave Foundry configuration and application authentication with their existing owners.

## Choose the transport

| Video transport | Illustrative destination ports | Example architecture |
| --- | --- | --- |
| HTTPS requests or WebSockets over HTTPS | TCP 443, then backend TCP 8080 or 8443 | ALB with an HTTPS listener |
| RTSP with interleaved RTP and RTCP | TCP 554 | Existing routed connection with one control/media TCP connection |
| RTSP with separate RTP and RTCP over UDP | TCP 554 plus configured UDP receiver ports | Existing routed connection with explicit media rules |

The ports are examples, not a Palantir specification. Some applications use a different RTSP port, allocate media ports per session or multiplex RTP and RTCP. Configure the actual application and its network policy together.

An ALB understands HTTP and HTTPS, including WebSocket upgrades. It cannot forward raw RTSP or UDP media. The HTTPS design therefore needs a compatible HTTP-based application or a separately deployed gateway; putting an ALB in front of an RTSP server does not convert its protocol. [AWS ALB listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)

## HTTPS through an ALB

The reusable module at the repository root creates an internal-by-default ALB in an existing VPC, an HTTPS listener, an IP target group, and separate ALB and backend security groups. Its runnable wrapper is [`examples/https-alb`](../examples/https-alb).

The path is:

```text
Verified client source
  -> ALB HTTPS listener on TCP 443
  -> backend HTTP on TCP 8080, or explicitly configured HTTPS on TCP 8443
```

The ALB accepts TCP 443 only from supplied source CIDRs. Its egress rule allows the configured backend port only to the backend security group. The backend group accepts that port only from the ALB group. Health checks use the same backend port, so they do not require an additional broad rule.

Supply subnets in different Availability Zones and an existing regional ACM certificate matching the hostname clients will request. The module checks subnet VPC membership and distinct zones. It does not create DNS records: the application’s DNS owner must point the chosen hostname at the ALB. The AWS-generated ALB hostname is not a replacement for your certificate’s hostname. [AWS HTTPS certificates](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/https-listener-certificates.html)

An internal ALB requires a working private path from the actual client or gateway. An internet-facing choice requires public routing and an explicit exposure review. Neither a security group nor a DNS record creates that route.

The default backend is HTTP on port 8080. To encrypt that hop, configure an HTTPS-capable backend and set both `backend_protocol = "HTTPS"` and `backend_port = 8443`. ALB does not validate target certificates, so backend encryption must not be described as backend mutual TLS or verified application identity. [AWS target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)

Target registration is deliberately explicit. `target_ips` is empty by default; a workload owner can register targets using the module’s target group output. If this example owns the registration instead, supply private IP targets whose interfaces carry the backend security group in the same VPC. An IP address in Terraform does not attach that group or start the application.

For an AWS workload initiating HTTPS to Foundry, the module can separately create an outbound client security group limited to supplied destination CIDRs on TCP 443. This is a distinct connection, not a reverse ALB rule. The application, destination management, routing and authorization still need configuration.

## RTSP control and media

RTSP controls a session. RTP carries media packets, and RTCP carries control information such as reports and feedback for the media session. Which sockets carry those packets depends on the negotiated transport.

With interleaved TCP, media is framed inside the RTSP TCP connection. This reduces the number of network flows to allow, but packet loss on TCP can affect timely delivery because later data waits behind missing bytes. Interleaving is a transport choice, not a guarantee of low latency or codec compatibility. [RTSP interleaved data](https://www.rfc-editor.org/rfc/rfc7826.html#section-14)

[`examples/rtsp-tcp`](../examples/rtsp-tcp) creates one security group for one selected AWS role:

- `aws_role = "server"`: a remote client initiates RTSP to the AWS server, so the group allows ingress on the configured control port.
- `aws_role = "client"`: AWS initiates RTSP to a remote server, so the group allows egress to that server’s control port.

Responses on the established TCP connection are statefully tracked. The example does not add UDP rules. Confirm the player actually negotiated interleaved transport; a client that falls back to UDP requires a different policy.

The remote RTSP server is not necessarily Foundry. Do not assume Foundry exposes an RTSP endpoint simply because an AWS-client pattern exists.

## Separate RTP and RTCP over UDP

For separate media, the client first establishes RTSP control. The peers agree on media destinations, and the server then sends packets to the receiver. A successful control connection says nothing about whether those UDP packets can reach the selected address and port.

The UDP example uses these illustrative receiver ports:

| Packet flow | Destination | Example port |
| --- | --- | --- |
| Client initiates RTSP | Server | TCP 554 |
| Server sends RTP | Client | UDP 5004 |
| Server sends RTCP | Client | UDP 5005 |
| Client sends RTCP feedback | Server | UDP 6001 |

These assignments explain direction; they are not inferred by Terraform. RTCP is not universally “RTP plus one.” Explicitly signaled ports and multiplexed configurations must be interpreted according to the application and transport profile. [RTP port conventions](https://www.rfc-editor.org/rfc/rfc3550.html#section-11)

For an AWS server, Terraform allows inbound RTSP control, outbound RTP and RTCP to the client, and inbound RTCP feedback. For an AWS client, those directions reverse. Each rule describes a **destination** port: ingress refers to the AWS receiver, while egress refers to a remote receiver.

[`examples/rtsp-udp`](../examples/rtsp-udp) exposes that model directly:

```hcl
# AWS hosts the RTSP server; the remote client pulls the stream.
aws_role       = "server"
peer_ipv4_cidrs = ["192.0.2.10/32"] # Documentation address; replace it.
rtsp_port      = 554

client_rtp_ports  = { from = 5004, to = 5004 }
client_rtcp_ports = { from = 5005, to = 5005 }
server_rtcp_ports = { from = 6001, to = 6001 }
```

Changing `aws_role` to `client` changes the AWS rule directions; it does not change the application into a client. Configure the application separately. Use peer CIDRs as actually observed after any translation, not an address copied blindly from SDP.

The module supports narrow ranges for explicitly configured receiver pools and limits each range to 32 ports as a lab guardrail. Multiple sessions may need different ports. Establish a port-allocation strategy before increasing capacity; do not solve a missing-media problem by opening every UDP port.

Security groups are stateful, but a TCP control session does not authorize an independent UDP media flow. Inspect all groups attached to the interface, because their permissions combine. Stateless NACLs and host firewalls also need to accommodate the intended traffic and return path. [AWS security group behavior](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html)

## Why an NLB is not automatically the answer

An NLB can forward TCP and UDP traffic on configured listeners. That is useful when endpoints, ports and target selection are controlled. It does not follow that every RTSP session can be placed behind one without additional design. [AWS NLB listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-listeners.html)

The remaining questions are architectural: which peer receives the media, what addresses are advertised, how does NAT affect them, and do independently forwarded control and media flows reach the correct session? A transport listener does not implement RTSP negotiation or a media-aware application gateway.

For this separate-media example, the starting point is an existing routed connection. If a load balancer or gateway is required, verify the application’s fixed-port or negotiated-port behavior, backend affinity, failover and concurrent sessions before adding it. A gateway also becomes an application that needs patching, authentication and capacity management.

## Provision a lab deliberately

All examples require an existing VPC and a verified route. The HTTPS example additionally needs suitable subnets, a certificate and a backend. The RTSP examples create security groups only: no server, NLB, routes or network-interface associations.

From the repository root, run the offline checks first:

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
python scripts/validate.py
```

The validation runner initializes the pinned provider, validates all examples and runs mocked Terraform tests. Provider downloads require registry access; these checks need no AWS credentials and do not deploy resources. A mock verifies Terraform behavior, not a live Foundry session.

Next, choose a single example. For separate media:

```sh
cd examples/rtsp-udp
cp terraform.tfvars.example terraform.tfvars
```

In PowerShell, use `Copy-Item -LiteralPath terraform.tfvars.example -Destination terraform.tfvars` instead of `cp`. Edit the copied file to set the real account, region, VPC, role, peer CIDRs and ports. Keep it out of Git. Authenticate using your approved AWS workflow, then inspect identity and create a saved plan:

```sh
aws sts get-caller-identity
terraform init
terraform validate
terraform plan -out=lab.tfplan
```

The provider account allowlist rejects credentials for an account other than `aws_account_id`. Review the plan’s resource ownership, exposure, costs and intended directions. Only after that review should you run `terraform apply lab.tfplan`.

Attach the resulting security group through the stack that owns the intended network interfaces. Do not replace an interface’s entire security-group list as a shortcut. Preserve other required application flows, and review their combined permissions.

## Test the stream rather than just the socket

Use an authorized disposable stream and the real client network path. Verify the authenticated control session, negotiated transport, receiver addresses and selected ports. For UDP, prove that RTP packets reach the client and produce decoded video; separately check RTCP where required. For interleaved transport, verify that the player did not silently choose a different transport.

Then test sustained playback, reconnects, idle periods and more than one client. If control works but video does not, inspect negotiated addressing, NAT, receiver bindings and media directions before changing the firewall. If packets arrive but cannot be decoded, investigate payload and codec compatibility instead of widening network access.

RTSP/RTP may carry unencrypted content. Neither private addressing nor a security group supplies encryption. Choose a verified encrypted network path or compatible application-layer TLS/SRTP controls, and keep credentials and captures out of the repository.

The [acceptance checklist](../VALIDATION.md) separates configuration tests from live integration evidence. Keep that distinction through deployment: a clean Terraform plan is the beginning of connectivity validation, not its conclusion.
