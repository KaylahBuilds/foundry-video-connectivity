# HTTPS connectivity through an ALB

Use this example only for an application or gateway that provides HTTP(S) semantics supported by the receiving Foundry integration. It does not convert RTSP or RTP, install a server or configure Foundry.

## Resources and defaults

Creates an internal IPv4 ALB, HTTPS listener on TCP 443, HTTP IP target group on TCP 8080, and separate ALB/backend security groups. The listener requires your existing regional ACM certificate. Application requests and health checks use the same backend port. Deletion protection is enabled.

`foundry_source_cidrs` allows incoming HTTPS from the **actual observed source**, which might be an approved worker, agent or gateway rather than a fixed global Foundry range. The backend accepts only the ALB security group on `backend_port`; ALB egress is limited to that backend group and port.

Bring two subnets in different Availability Zones in the same VPC. An internal ALB requires a private routed path from the client. Setting `internal = false` is an explicit exposure change, not an automatic route configuration. Public deployments also require suitable internet-connected subnets, correct DNS and an approved source allowlist.

`target_ips` is empty by default. Either supply stable keys mapped to private IP addresses **whose network interfaces carry the backend security group in the same VPC**, or let ECS/EKS/another workload owner register targets using `target_group_arn`. This module does not attach security groups to existing interfaces. A registered address alone does not grant traffic, and an empty target group cannot deliver a stream.

## Configure and plan

Use the Bash or PowerShell copy command, not both:

```sh
# Bash, from this example directory
cp terraform.tfvars.example terraform.tfvars
```

```powershell
# PowerShell, from this example directory
Copy-Item -LiteralPath terraform.tfvars.example -Destination terraform.tfvars
```

Replace all documentation placeholders. The sample account, VPC, subnet IDs, certificate and CIDRs do not identify working resources. Authenticate through your approved local AWS workflow, then:

```sh
aws sts get-caller-identity
terraform init
terraform validate
terraform plan -out=lab.tfplan
```

Review the saved plan, expected account and costs. Only after review:

```sh
terraform apply lab.tfplan
```

Keep state and saved plans private. Configure an encrypted, access-controlled remote backend before shared operational use; this lab does not create one.

## Backend encryption and client identity

To encrypt the backend hop, set `backend_protocol = "HTTPS"` and `backend_port = 8443` and configure a TLS-capable backend on that port. ALB does not validate target certificates; this is not backend mutual TLS or verification of application identity. Front-end clients must still validate the hostname and certificate. Configure a DNS alias using `alb_dns_name` and `alb_zone_id` through your DNS owner; do not expect the AWS-generated hostname to match your custom ACM certificate. [AWS target-group TLS behavior](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)

Network allowlisting does not authenticate a video user. Configure application authorization and protect stream URLs separately. Return minimal information from the health endpoint.

## Optional outbound HTTPS and logging

Set `enable_outbound_client = true` with `foundry_destination_cidrs` to create a separate client security group for an AWS workload initiating HTTPS to those addresses. Attach it through the workload's owner. It does not configure Foundry's API, DNS allowlisting, NAT or the application. Destination IPs can change; use a managed and reviewed egress design for services without stable ranges.

To enable ALB access logs, set `access_log_bucket` to an existing delivery-compatible S3 bucket and optionally `access_log_prefix`. Its bucket policy, encryption, retention and privacy controls stay with the bucket owner. Never place bearer tokens in URL query strings; access logs may contain request details.

## Validate and clean up

Check target registration/health, the requested hostname and certificate, application authentication, an actual supported video request, and sustained connections. Idle timeout and reconnect behavior must suit the application; defaults are not a video performance guarantee. Complete the [live checklist](../../VALIDATION.md).

An ALB incurs ongoing charges even when idle. For cleanup, first remove workload registrations/associations managed elsewhere. Disable `deletion_protection` through a reviewed plan/apply, then review a destroy plan for this example only. Do not destroy the existing VPC, certificate, log bucket or shared workloads. Preserve any evidence required by your retention policy.
