# RTSP with interleaved TCP media

This alternative creates a new security group for an existing routed connection. It does not create a video service, connector, NLB, routes, or network interface attachments.

Set `aws_role` to the role of the AWS interface:

- `server` (default): permit the named remote peers to initiate RTSP to AWS on TCP `rtsp_port` (554 by default).
- `client`: permit AWS to initiate RTSP to the named remote peers on their TCP `rtsp_port`.

There are **no UDP rules**. Both applications must use RTP/RTCP interleaved over the control connection. A client silently falling back to UDP will not be supported by these rules. Foundry RTSP support is a prerequisite to verify, not a feature this example establishes.

## Review, then plan

1. Obtain the intended AWS account ID, region, VPC ID, actual peer addresses as seen at AWS, and server port. Confirm private routing and application authentication separately.
2. Copy the sample to a local ignored file:

   ```sh
   cp terraform.tfvars.example terraform.tfvars
   ```

   PowerShell equivalent: `Copy-Item terraform.tfvars.example terraform.tfvars`.
3. Replace **all** placeholders. The all-zero account ID is intentionally rejected. `192.0.2.10/32` is a documentation address, not a Foundry source range. Use trusted short-lived AWS authentication outside Terraform files.
4. From this example directory:

   ```sh
   terraform init
   terraform fmt -check
   terraform validate
   terraform plan -out=stream.tfplan
   terraform show stream.tfplan
   ```

   The provider checks `aws_account_id` against the authenticated account. The plan must contain only the intended new group and one TCP flow per peer. Review role, region, account, VPC, and peers before any apply. Plans and state may contain sensitive infrastructure information; keep them private and out of Git.
5. Only after an authorized review, apply the exact saved plan with `terraform apply stream.tfplan`. Attach the output group through the interface owner's configuration. Applying this example alone does not connect the video service.

An AWS server needs no unrelated all-open egress rule for replies on its admitted TCP connection. Other attached groups may broaden permissions because AWS combines their allow rules. See [AWS security group rules](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html).

## Test the real stream

Check authenticated session setup, the negotiated **interleaved TCP** transport, decoded video, RTCP where used, sustained playback, and reconnection from the intended client path. Verify packet captures do not contain credentials before sharing them. A successful port probe is not a stream test.

Plain RTSP/RTP is not protected by a security group. Use an approved encrypted private path or verified application encryption. Authentication and an allowlisted address do not provide transport encryption. See the [module's security boundaries and flow table](../../modules/rtsp-security-groups/).

For cleanup, first remove the association through the owning infrastructure and verify that no other workload uses the group, then review `terraform plan -destroy` before `terraform destroy`. Do not destroy a group still required by a live service.
