# Mail DNS

This directory holds the `SPF`, `DKIM`, and `DMARC` records that platform mail uses to authenticate. There is one file per environment, per [ADR-0307](../../docs/adr/0307-outbound-email.md).

**Records, not a provider.** [ADR-0200](../../docs/adr/0200-cluster-topology.md) leaves provisioning to the project. `infra/terraform/` holds a README and no modules. So these files state the record content, and the tool that manages the zone applies it. A Terraform module, a provider console, and a zone file all read the same lines.

**Why these are committed and not set once by hand.** A mail sender's reputation lives in three records. They are invisible when correct and silent when wrong. For example, take a message signed with a key whose `DKIM` record was never published. It fails at the receiver, the sender accepts it, and this side reports nothing. The records belong under review for the same reason that the DKIM key belongs under SOPS.

## Applying them

1. Provision the dedicated egress IP, and request its `PTR` record from the provider.
2. Make sure the `PTR` record resolves to the `hostname` in `infra/helm/platform/maddy/values.yaml`. Every major receiver treats a mismatch between HELO name and reverse DNS as a strong negative signal. It fails at the first send.
3. Generate the DKIM keypair once. maddy writes both halves when `key_path` is absent.
4. Put the private half in the environment's SopsSecret as `maddy-dkim`, and the public half in the `DKIM` record.
5. **Never let the pod create its own key.** It then signs with a key that no record matches. Every message fails authentication, and nothing shows as unhealthy.
6. Publish the records.
7. Send one message, and read the receiver's authentication results before you trust the path.
8. Keep `DMARC` at `p=none` until the aggregate reports are clean, then move to `p=reject`. An environment is not production until it has `p=reject`, per [ADR-0307](../../docs/adr/0307-outbound-email.md).

## What is absent on purpose

- **No `MX` record for the mail subdomain.** The platform sends and does not receive. An `MX` record would advertise an inbound path that no listener serves.
- **No MTA-STS policy.** A receiver publishes that policy, and this platform is not a receiver. maddy *consumes* the policies that its recipients publish, and that needs no record here.
- **No records for human mailboxes.** Human mail is a separate sender with its own egress IP and `DKIM` selector, and it serves the organisation domain's `MX`. If the two merge, platform mail loses the reputation benefit that put it on a subdomain.
