# Validation and acceptance checklist

Offline checks validate configuration and project assumptions. Integration checks validate a real application, network path and connector. They answer different questions.

## Local and CI checks

From the repository root:

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
terraform fmt -check -recursive
python scripts/validate.py
```

The runner initializes and validates the root HTTPS module, the RTSP module and all three example roots. It runs native mocked Terraform tests for both modules. Terraform downloads the pinned AWS provider during initialization, even for mocks. No AWS credentials or cloud resources are required for these checks.

If Terraform is not on PATH, use `python scripts/validate.py --terraform /path/to/terraform`. For local source-level checks alone, use `python scripts/validate.py --contracts-only`. A source-level pass is not a substitute for `terraform validate` and `terraform test`.

- [ ] Recursive formatting passes.
- [ ] Initialization and provider-backed validation pass in all five roots.
- [ ] HTTPS mock tests exercise default private exposure, SG references, listener TLS, backend settings, optional resources and rejected inputs.
- [ ] RTSP mock tests exercise both client/server roles, TCP/UDP modes, exact directional rules, custom ports, duplicate media ports and rejected inputs.
- [ ] Repository tests check the validation workflow, example hygiene and command restrictions.
- [ ] Review dependency changes and generated `.terraform.lock.hcl` checksums before committing legitimate lock files. Never fabricate a lock file when downloads fail.
- [ ] Review every staged file for credentials, real endpoint details, state, plans, captures and logs.

## Confirm the integration before provisioning

- [ ] Identify the actual Foundry connector or gateway, version, owner and supported protocols. A generic Foundry streaming feature is not proof of RTSP support.
- [ ] Identify where the client and server run, and which party initiates control.
- [ ] Record the actual RTSP version, control port, media transport, codec and authentication method.
- [ ] For UDP, confirm receiver ports, RTCP feedback ports, port allocation per concurrent session, multiplexing and advertised addresses.
- [ ] Identify source and destination addresses as observed after any NAT, proxy or gateway. Verify allowed CIDRs with the service owner.
- [ ] Confirm an existing routed path. Private DNS resolution does not establish private routing.
- [ ] Review encryption for both control and media, data sensitivity, retention and expected cloud charges.

## Review the AWS plan

- [ ] Verify the caller account and selected region; set `aws_account_id` explicitly.
- [ ] Use a disposable lab or isolated test resources. Inspect every new security group and port direction in the saved plan.
- [ ] For ALB, verify subnet VPCs, distinct Availability Zones, routes, certificate region/status/hostname, intended internal/public setting and application health path.
- [ ] Confirm target registration ownership and how the backend SG is attached to target interfaces.
- [ ] Inspect all other groups attached to those interfaces; their permissions combine.
- [ ] Check both directions of stateless network ACLs, including return ports. Do not open broad ranges as a substitute for identifying a missing flow.
- [ ] Configure a private state backend and approve the provisioning role before shared operational use.

## Verify HTTPS end to end

- [ ] Use the intended hostname, validate the certificate chain and verify application authorization.
- [ ] Verify target registration and health. A healthy HTTP endpoint alone does not prove video delivery.
- [ ] Test a supported video request through the actual Foundry worker or approved gateway.
- [ ] Verify backend encryption if configured, idle behavior, reconnection, sustained playback and expected concurrent clients.
- [ ] Confirm unauthorized source networks and unauthenticated requests are rejected by the intended layer.

## Verify RTSP and separate media

- [ ] Establish an authenticated RTSP session from the real client location.
- [ ] Record sanitized SETUP/Transport and SDP results; verify selected transport and reachable receiver addresses.
- [ ] For TCP interleaving, prove media actually uses the control connection, not a negotiated fallback to UDP.
- [ ] For UDP, verify RTP reaches the selected client ports and produces decodable video.
- [ ] Verify RTCP reports/feedback where the application requires them; do not infer it from RTP success.
- [ ] Test session teardown, reconnect, NAT timeout behavior, long-running streaming, packet loss and concurrency.
- [ ] Confirm an unauthorized peer cannot establish a session, and that the stream's authentication/encryption matches policy.

Use only your own authorized lab endpoints. Packet captures must be private and sanitized; do not commit recordings or credential-bearing control messages.

## Troubleshoot by symptom

| Symptom | First checks |
| --- | --- |
| TCP control cannot connect | Correct destination port, routes, peer address, security groups, NACLs and server listener |
| RTSP works but video is absent | Negotiated UDP destination, advertised IP, NAT behavior, media-direction rules and receiver binding |
| Packets arrive but video will not decode | Codec/profile support, payload format, encryption keys and application behavior |
| Stream stops after an idle period | Connection/NAT timeouts, keepalives and reconnect behavior |
| One client works but several fail | Per-session port allocation, receiver collisions, capacity and any forwarding affinity |
| ALB returns an error | Target registration, health path, backend port/protocol, SG attachment and application logs |

## Cleanup

- [ ] Stop lab sessions and preserve required evidence privately.
- [ ] Remove associations and registrations using their owning stack.
- [ ] Disable ALB deletion protection through a reviewed change when cleanup is intended.
- [ ] Review a destroy plan for the selected example, then remove only its resources.
- [ ] Check for remaining chargeable ALBs, retained access logs and private state. Existing VPCs, certificates, gateways and log buckets are not owned by these examples.

## Current verification status

On October 12, 2026, [GitHub Actions validation](https://github.com/KaylahBuilds/foundry-video-connectivity/actions/runs/38303819131) passed all 9 repository checks, recursive Terraform formatting, initialization and provider-backed validation in all five roots, and all 50 native mocked Terraform tests (27 HTTPS and 23 RTSP). Local relative documentation-link checks also passed. Local provider initialization remains blocked by registry DNS access, so the provider-backed results come from GitHub Actions rather than this workstation.

These results verify configuration and mocked behavior, not live connectivity. No AWS apply or Foundry integration test has been performed, and no stream has been connected. Complete the integration and acceptance checklists above before operational use.
