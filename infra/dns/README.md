# DNS

This directory declares every record in every zone that this project owns. `mise run dns:apply` applies it, per [ADR-0206](../../docs/adr/0206-cluster-networking.md) and [ADR-0307](../../docs/adr/0307-outbound-email.md).

**This directory is the zone.** `mise run dns:apply` deletes every record that the provider holds and `dnsconfig.js` does not declare. A record added in the provider's console lives until the next apply. To add one, open a pull request. `mise run dns:check` reports the difference and changes nothing. It fails when the two differ, and that keeps the repository and the provider from drifting apart.

## Files

| Path | What it is |
| --- | --- |
| `dnsconfig.js` | the zones, as [dnscontrol](https://docs.dnscontrol.org/) declarations |
| `creds.json` | the provider. It names environment variables and holds no secret |
| `secrets.enc.yaml` | the values of those variables, SOPS-encrypted, per [ADR-0202](../../docs/adr/0202-secrets.md). The template ships none |

## Adopt

The template ships placeholders, because a project chooses its own provider and addresses.

1. In `creds.json`, replace the `zone` entry with the project's provider. Each credential field names an environment variable, for example `"apitoken": "$DNS_API_TOKEN"`.
2. Create `secrets.enc.yaml` with one `stringData` key per variable, and encrypt it with `sops --encrypt --in-place`. `scripts/dns.sh` decrypts it for the length of one command.
3. Scope the credential to read and edit the project's zones, and nothing wider.
4. In `dnsconfig.js`, replace each placeholder address with the environment's edge address and mail egress address.
5. Run `mise run dns:check`, read the difference, then run `mise run dns:apply`.

`mise run lint:dns` checks the declaration with no credential, so it runs in CI.

## What a wildcard covers

[ADR-0206](../../docs/adr/0206-cluster-networking.md) puts one wildcard `A` record per environment in front of the edge. So a new service needs no record, and `external-dns` is not deployed. [ADR-0306](../../docs/adr/0306-trust-tiers-and-urls.md) adds the second wildcard: `*.<env>` does not match a name that is two labels deep, so the ops tier has its own.

## Mail records

A mail sender's reputation lives in three records: `SPF`, `DKIM`, and `DMARC`. They are invisible when correct and silent when wrong. For example, take a message signed with a key whose `DKIM` record was never published. It fails at the receiver, the sender accepts it, and this side reports nothing.

1. Provision the dedicated egress IP, and request its `PTR` record from the provider.
2. Make sure the `PTR` record resolves to the `hostname` in `infra/helm/platform/maddy/values.yaml`. Every major receiver treats a mismatch between HELO name and reverse DNS as a strong negative signal. It fails at the first send.
3. Generate the DKIM keypair once. maddy writes both halves when `key_path` is absent.
4. Put the private half in the environment's SopsSecret as `maddy-dkim`, and the public half in the `dkim` field of `dnsconfig.js`.
5. **Never let the pod create its own key.** It then signs with a key that no record matches. Every message fails authentication, and nothing shows as unhealthy.
6. Run `mise run dns:apply`.
7. Send one message, and read the receiver's authentication results before you trust the path.
8. Keep `DMARC` at `p=none` until the aggregate reports are clean, then move to `p=reject`. An environment is not production until it has `p=reject`, per [ADR-0307](../../docs/adr/0307-outbound-email.md).

`PTR` records are not in this directory. The hosting provider sets them against the address, not against the zone.

## What is absent on purpose

- **No `MX` record for the mail subdomain.** The platform sends and does not receive. An `MX` record would advertise an inbound path that no listener serves.
- **No MTA-STS policy.** A receiver publishes that policy, and this platform is not a receiver. maddy *consumes* the policies that its recipients publish, and that needs no record here.
- **No records for human mailboxes in the template.** Human mail is a separate sender with its own egress IP and `DKIM` selector, and it serves the organisation domain's `MX`. A project that has such records declares them in `dnsconfig.js`, because the apply deletes what the file omits.
