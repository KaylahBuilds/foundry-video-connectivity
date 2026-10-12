# RTSP control with separate RTP/RTCP over UDP

This alternative creates a new security group for a **pull session** on an existing routed path. It does not create a streaming server, connector, load balancer, VPN, routes, NAT, or interface attachments. Confirm the Foundry connector actually supports this transport before deployment.

## Receiver ports, not source ports

| Input | Default | AWS is `server` | AWS is `client` |
| --- | --- | --- | --- |
| `rtsp_port` | TCP 554 | Inbound control | Outbound control |
| `client_rtp_ports` | UDP 5004 | Outbound to client | Inbound to AWS |
| `client_rtcp_ports` | UDP 5005 | Outbound to client | Inbound to AWS |
| `server_rtcp_ports` | UDP 6001 | Inbound feedback | Outbound feedback |

These assignments are **illustrative, not Palantir requirements**. Set `aws_role` to `server` when a remote client pulls from AWS, or `client` when AWS pulls from a remote server. The default is `server`. The module creates only the selected role's rules.

Each UDP input is an inclusive `{ from, to }` destination range of at most 32 ports. For example, `client_rtp_ports = { from = 10000, to = 10007 }` permits eight client receiver ports. This does not tell an application to negotiate those ports; configure the application and verify its negotiation separately.

RTP and RTCP assignments are independent; do not assume RTCP is always RTP plus one. A TCP RTSP connection does not authorize separate UDP traffic. Both directions of RTCP are explicit. If a supported application negotiates RTP/RTCP on an identical receiver port, the module deduplicates that SG rule but does not configure multiplexing. See the [module contract](../../modules/rtsp-security-groups/) and [RTP specification](https://www.rfc-editor.org/rfc/rfc3550.html).

## Configure and review

1. Confirm routing and the addresses visible at the AWS interface, including translation effects. Obtain verified account, region, VPC, and peer CIDRs. Prefer individual `/32` peers.
2. Copy the sample:

   ```sh
   cp terraform.tfvars.example terraform.tfvars
   ```

   PowerShell: `Copy-Item terraform.tfvars.example terraform.tfvars`.
3. Replace every account/network placeholder and choose the AWS role. The all-zero `aws_account_id` is intentionally invalid. The sample peer `192.0.2.10/32` is a documentation address, **not a Foundry address**. Set real receiver ports from both applications. Do not add credentials or credential-bearing stream URLs.
4. Use approved temporary AWS credentials outside this directory, then run:

   ```sh
   terraform init
   terraform fmt -check
   terraform validate
   terraform plan -out=stream.tfplan
   terraform show stream.tfplan
   ```

5. Review the exact account, VPC, role, protocol, and destination of every rule. The provider rejects a different authenticated AWS account. Apply only the reviewed plan after authorization with `terraform apply stream.tfplan`.
6. Associate the new `security_group_id` through the infrastructure that owns the AWS client/server interface. Inspect all other attached groups: their permissions can broaden access. This example does not modify those groups or attach itself.

Keep plans and state private and out of Git. If the real application needs more than this bounded example supports, review its flow design instead of opening all UDP ports.

## Verify data, not just control

Run a complete authenticated pull session from the intended client. Confirm the RTSP-selected transport, advertised receiver addresses, and ports; verify RTP arrives and video decodes; then inspect RTCP, sustained playback, and reconnection. Record expected and observed flows without exposing stream secrets.

When control works but video does not, inspect the receiver address advertised in session metadata, route symmetry, NAT, network ACLs, operating-system firewalls, and actual bound receiver ports. Fix mismatches at the appropriate layer. An NLB does not rewrite RTSP negotiation or automatically arrange these flows.

Use an approved encrypted private path, or independently supported and verified control TLS and media SRTP. Plain RTSP/RTP plus a private CIDR or SG is not encryption. Control-channel TLS alone does not secure separate UDP media.

For cleanup, remove the association through the owning infrastructure after confirming no live workload needs it. Review `terraform plan -destroy` before `terraform destroy`.
