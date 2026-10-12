# Security boundaries

## Never commit credentials

Use AWS SSO, workload identity or an approved profile outside this repository. No example accepts AWS keys, Foundry tokens, camera credentials or passwords as Terraform inputs. Never embed credentials in a stream URL. Do not print credential environments, record authenticated headers or paste secret values into commands.

Git ignores populated variable files, state, saved plans, local credential directories, keys and packet captures. Ignore rules do not remove files already tracked or prevent a forced add. Inspect the actual proposed commit before pushing. The local test suite performs only heuristic checks, not a comprehensive secret scan. If a credential is exposed, revoke or rotate it first and follow your incident process; deleting the latest file is insufficient.

Terraform state, plan output and resource names can reveal network topology even without secrets. Protect them in private storage. Do not upload plans, captures, video, source addresses or stream identifiers to public CI artifacts.

## Scope network access deliberately

Every example uses IPv4 only, explicit peer/source CIDRs and selected destination ports. There are no default Internet-wide rules. Requiring a nonzero prefix length is a guardrail, not proof that a supplied CIDR is narrow enough. Review the aggregate allowed addresses against approved endpoints and SG quotas.

Security groups are additive. Another group attached to an interface can allow traffic this module omits. Check all attached groups, NACLs, operating-system firewalls, routes and middleboxes. Return-traffic tracking for RTSP over TCP does not grant a new UDP media flow. The module includes explicit media directions for its supported pull-session model. [AWS security group rules](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html)

The AWS role selects which party initiates RTSP control. It is not a Foundry permission or a substitute for protocol support. The wrappers create new groups and leave interface association to the workload owner. Do not use an unreviewed attach command against production interfaces to make a test pass.

## Encryption and authentication

The ALB terminates front-end TLS. Backend HTTP is plaintext; choose HTTPS where the threat model requires backend encryption. ALB does not validate target certificates, so HTTPS backend configuration is not backend identity verification. User authentication and authorization belong to the application or a separately designed gateway. [AWS target-group protocol behavior](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)

RTSP control and RTP media may both be plaintext. An internal address and a security group do not encrypt either. Use a verified encrypted private transport or supported RTSP TLS/SRTP configuration. A private circuit alone is not a promise of encryption. Review the transport and application security together, and do not expose an unauthenticated camera server to the Internet.

A Network Load Balancer is a transport forwarder, not a protocol converter, authentication layer or RTSP-aware media gateway. These examples do not dynamically open negotiated ports or rewrite SDP. A gateway, if required, needs its own hardening, patching, authentication, scaling and failure testing.

## Deployment and CI authority

The only workflow validates and runs mocked tests. It has read-only repository permissions, pinned actions, no cloud login, no OIDC write permission, no secrets and no real apply. No contribution should obtain deployment authority merely by changing a rule or test. Review Terraform/provider/action upgrades and run CI before merging them.

The deployable wrappers require the expected AWS account ID and use the provider's account allowlist. This prevents an accidental wrong-account use; it does not restrict the permissions of the credentials you supply. Use a disposable account and a least-privilege provisioning role, protect remote state and require a plan review.

## Logging and privacy

An ALB access-log bucket is optional and externally owned. Before enabling logs, configure the required delivery policy, supported encryption, retention and access restrictions. URLs can reveal stream identifiers; never put tokens in query strings. Packet captures and video can contain confidential content and personal information. Use synthetic or explicitly authorized lab data, short retention and restricted access.

## Report a problem

Do not post credentials, real stream URLs, production captures or sensitive topology in a public issue. Share a sanitized reproduction, affected example and Terraform/provider versions with the repository owner through an approved private channel. Report vendor vulnerabilities through the relevant vendor's disclosure process.
