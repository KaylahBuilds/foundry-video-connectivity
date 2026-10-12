# AWS connectivity for Foundry video integrations

Terraform examples for connecting an AWS-hosted video application or client to a **verified, compatible Palantir Foundry integration**. Choose the protocol and client/server role first, then configure the network rules. These are networking building blocks, not a Foundry connector or a working video service.

The [companion article](docs/article.md) explains the architecture from the supplied draft. Start with [the examples guide](examples/README.md) to choose an implementation, and complete [the validation checklist](VALIDATION.md) before deployment.

## Choose an example

| Transport | Example destination ports | What Terraform creates |
| --- | --- | --- |
| HTTPS delivery or WebSockets over HTTPS | TCP 443 to ALB; TCP 8080 or 8443 to backend | [Internal-by-default ALB, listener, target group and scoped security groups](examples/https-alb) |
| RTSP with interleaved RTP and RTCP over TCP | TCP 554 | [A role-specific security group](examples/rtsp-tcp) for an existing routed connection |
| RTSP control with separate RTP and RTCP over UDP | TCP 554; illustrative UDP 5004, 5005, 6001 | [A role-specific security group](examples/rtsp-udp) with explicit media directions |

**None of these ports or CIDRs are Palantir requirements.** Obtain the actual protocol support, peer addresses, source ranges and media-port behavior from your application and Foundry administrator. Foundry data streaming documentation does not establish that a connector accepts an RTSP camera feed.

The ALB supports HTTP and HTTPS, not raw RTSP or UDP. A Network Load Balancer supports TCP/UDP forwarding, but that alone does not handle RTSP negotiation, advertised media addresses, or control/media affinity. This project deliberately does not provision an NLB for a dynamically negotiated stream. [AWS ALB listener protocols](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html) · [AWS NLB listener protocols](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-listeners.html)

## Repository layout

```text
main.tf, variables.tf, outputs.tf    reusable HTTPS ALB module
modules/rtsp-security-groups/        reusable routed RTSP rule module
examples/https-alb/                  deployable HTTPS module wrapper
examples/rtsp-tcp/                   interleaved TCP wrapper
examples/rtsp-udp/                   separate UDP media wrapper
docs/article.md                     companion article draft
SECURITY.md                         credentials and exposure boundaries
VALIDATION.md                       offline and live acceptance checks
.github/workflows/validate.yml      validation only, no cloud deployment
```

## What stays outside Terraform

Bring your own VPC, routes, network interfaces, video server or client, and authentication. The HTTPS example also needs two suitable subnets in different Availability Zones and an existing regional ACM certificate. Private endpoints require an established routed private path from the actual worker or gateway. Public exposure requires an explicit choice plus correct subnets and routing.

These examples do not create VPNs, NAT, DNS, certificates, Foundry source configuration, protocol conversion, codecs, stream encryption, or Kubernetes resources. Security group IDs are outputs: attach them through the infrastructure that owns the intended network interfaces. Do not let two stacks independently manage the same attachment or target registration.

## Check without deploying

Use Python 3.11+ and Terraform **1.9.8** for the validation tooling. AWS provider **6.68.0** is pinned. Initialization needs access to the official provider registry; tests use a mocked provider and need no AWS credentials.

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
python scripts/validate.py
```

See [VALIDATION.md](VALIDATION.md) for what these checks prove and what still requires your accounts. There is no automated `terraform apply`, AWS login or secret-bearing CI job.

## Plan a disposable lab

1. Confirm the integration's actual protocol and whether the AWS endpoint is the **server** or **client**.
2. Choose one example; read its README before modifying it.
3. Copy its `terraform.tfvars.example` to a local `terraform.tfvars`, then replace every placeholder. The copied file is ignored by Git.
4. Authenticate with your approved AWS SSO/profile workflow. Each deployable wrapper requires `aws_account_id`; the provider refuses credentials for a different account.
5. Run `terraform init`, `terraform validate`, then `terraform plan -out=lab.tfplan` inside the chosen example. Review the account, region, CIDRs, ports, resources and costs before explicitly applying that saved plan.

Do not use an example's documentation addresses in a real deployment. Do not put credentials or credential-bearing stream URLs into Terraform, commits, terminal arguments, plans or screenshots. Read [SECURITY.md](SECURITY.md).

## Operational boundaries

HTTPS defaults to an internal ALB with deletion protection, TLS at the listener, and a backend port restricted by security group references. Backend HTTP remains plaintext; explicitly choose HTTPS where required. Optional access logging needs an existing correctly configured S3 destination.

RTSP examples create one security group for the selected role. The UDP rules distinguish control, receiver media and RTCP feedback. They use narrow configurable port ranges, not a broad ephemeral range. RTSP/RTP can be unencrypted: a private IP address and security group are not encryption. Use an approved encrypted network path or compatible application-layer security.

A passing Terraform test is not proof of connectivity. A successful RTSP handshake is not proof that video packets arrive or decode. Test the complete session and sustained streaming before treating the design as operational.

Independent educational examples; not endorsed by Palantir or AWS.
