# ADR-0307: Outbound Email

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0200](0200-cluster-topology.md), [ADR-0202](0202-secrets.md), [ADR-0205](0205-environment-parity.md), [ADR-0301](0301-data-lifecycle-privacy.md), [ADR-0302](0302-temporal.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0500](0500-observability.md)
- **Decides:** maddy submits outbound mail and signs DKIM from a dedicated static IP, with no inbound listener and no mailboxes.

## Context

Identity depends on mail. The Kratos flows of [ADR-0304](0304-identity-and-authorization.md) send address verification and account recovery, and neither has a fallback. An undelivered recovery mail is a locked-out user. Product notifications use the same path, dispatched through the outbox or a workflow, per [ADR-0302](0302-temporal.md).

[ADR-0000](0000-platform-foundations.md) ranks outbound email **first** to concede when the platform moves down axis B. Its main cost is not operational but **reputational**. To set up the server is a small task. To have its mail accepted is not. Receivers decide acceptance from the history of the sending IP, the authentication records of the domain, and complaint rates. Engineering effort cannot remove that cost. It can only accumulate it.

Two constraints shape every option:

- Many hosting providers block outbound port 25 by default.
- Residential and cloud IP ranges carry an existing reputation. The platform inherits it and does not earn it.

**Scope: outbound only.** The platform sends mail. It does not receive mail, host mailboxes, or run IMAP. So the inbound half of every mail suite is out of scope.

**Human mailboxes are a separate system, bought or self-hosted.** A team that wants `admin@example.com` as a real inbox needs correspondence: storage, IMAP, webmail, spam filtering, and retention. This shares a domain with transactional sending and little else. The two systems coexist and do not merge:

- `MX` points at the mailbox system.
- `SPF` lists both senders.
- Each sender signs with its own `DKIM` selector.

So a need for mailboxes never changes this decision. The choice of system for them is a separate choice, outlined under [If mailboxes are self-hosted](#if-mailboxes-are-self-hosted).

## Decision drivers

1. **Operational sovereignty**, per principle 3 of [ADR-0000](0000-platform-foundations.md). Mail leaves infrastructure that we control, as the product's own domain.
2. **The reputation asset is the domain and the IP**, not the software. Novelty is priced to match, per principle 4. A change of agent loses nothing that was earned.
3. **A sender shares its reputation with every other sender beside it.** The asset of driver 2 is as easy to spend as to earn. Any sender on the same IP and signing domain spends it. Account recovery has no fallback, and human correspondence does. So the two never share a sender.
4. **Thinnest viable platform**, per principle 2. A submission agent, not a mail suite.
5. **A change of sender costs a configuration change.** [ADR-0000](0000-platform-foundations.md) concedes this component first. So application code must not be able to reach the chosen sender directly.
6. **A silently dropped mail is visible as a metric**, not as a support ticket.

## Considered options

| Option | Sends as our domain | Component weight | What it costs | Verdict |
| --- | --- | --- | --- | --- |
| **maddy, submission and DKIM only** | yes | **one Go binary**, no datastore | we own IP warmup, blocklist monitoring, and DMARC reporting | **Chosen.** It holds principle 3 at the lowest component count. The software is cheap to change, because the reputation lives elsewhere *(reasoned)* |
| Postfix | yes | one daemon, plus its own spool | the same reputation work, plus a configuration language of its own | The boring choice, and principle 4 says to be boring where the exit costs months. Here the exit cost is a config rewrite, not a migration. The agent that sends does not affect the reputation. Rejected on operational legibility, not on maturity |
| OpenSMTPD | yes | one daemon | the same reputation work | The direct answer to the legibility complaint above. Its configuration language is the smallest of any full MTA. It loses narrowly on DKIM. DKIM is a filter to wire up, not a built-in. So the part this ADR most needs is the one part that does not come with it |
| Exim | yes | one daemon | the same reputation work, plus an expansion syntax of its own | It is built around an inbound routing and filtering surface, and this platform does not use that part |
| Haraka | yes | one Node.js service, plus the plugin set that makes it a mail server | the same reputation work. DKIM signing is a plugin, not a core path | A JavaScript runtime on the floor for a component that only sends, against [ADR-0100](0100-language-and-runtime.md) |
| A relay-only client: msmtp, nullmailer, or Postfix as a null client | **no**. It relays through another sender | none worth counting | none of the reputation work, because it does none of the sending | Not an alternative but a shape: it assumes the managed row below. The row matters because `self-host the SMTP endpoint` and `own the deliverability` are separate. Only the second is expensive |
| Stalwart | yes | one binary, broader scope | an inbound, JMAP, and mailbox surface that we do not use | Capable and young. Rejected because it carries the inbound half that this ADR puts out of scope. For exactly this reason, it is the preferred option [if mailboxes are self-hosted](#if-mailboxes-are-self-hosted) |
| Mailu or Mailcow | yes | a suite: several containers, a datastore, webmail, antispam | a full mail platform | Rejected by principle 2. These solve *running an email provider*, and that is not the problem |
| poste.io | yes | a suite in one container: Postfix, Dovecot, Rspamd, webmail, admin UI | a full mail platform, inbound included | Rejected by principle 2, together with Mailu and Mailcow. A suite in a single container lowers the operational count but not the surface. Mailboxes, IMAP, and antispam are still deployed and still out of scope |
| Postal | yes | Ruby, MariaDB, RabbitMQ | a second datastore and a second message broker | Rejected by principles 2 and 5 |
| Managed transactional provider, such as Postmark, SES, or Mailgun | yes | none | deliverability becomes the problem of someone else, and recipient metadata leaves our control | **The sanctioned exit**, ranked first on the swap list of [ADR-0000](0000-platform-foundations.md). Not the default, because principle 3 is a constraint, not a preference |
| Do nothing, the honest baseline | does not apply | none | nothing | Account verification and recovery have no delivery path, so identity is unusable |

### The non-production sink

A sink is chosen for the property that the agent above is chosen against: it must not deliver.

| Option | Reading a message | Runtime cost | Verdict |
| --- | --- | --- | --- |
| **Mailpit** | an HTTP API over the same store that the UI reads | one Go binary, no datastore | **Chosen.** The API lets an e2e test assert delivery, not only a human see it *(reasoned)* |
| MailHog | an HTTP API and a UI | one Go binary | The unmaintained predecessor of Mailpit |
| smtp4dev | an HTTP API and a UI | a .NET runtime on the floor | Rejected by [ADR-0100](0100-language-and-runtime.md), for a component that exists only below production |
| maddy, the production agent | needs the mailbox and IMAP surface that this ADR puts out of scope, plus an IMAP client in the test suite | one Go binary, plus a mailbox store | Rejected. Its special configuration is DKIM, `PTR`, DANE, and MTA-STS. Without public DNS and real receivers, none of it has anything to act on. So it runs a configuration that ships nowhere. A correctly configured maddy also delivers. That makes the never-deliver rule a setting, not a property |
| A logging sink | the raw message in a log line | none | It loses the rendered message, and with it the recovery link that a flow test follows |
| No sink | nothing to read | none | Identity flows cannot run below production |

## Decision

| Concern | Decision |
| --- | --- |
| Agent | **maddy**, configured as a submission endpoint and DKIM signer. No inbound listener, no mailboxes |
| Egress | a **dedicated static IP** whose `PTR` resolves to `mail.example.com`, which matches the HELO name of maddy. Mail does not use shared or dynamic egress |
| Authentication records | platform mail authenticates as `mail.example.com`. That subdomain carries the [`SPF`](https://www.rfc-editor.org/rfc/rfc7208) record and [`DKIM`](https://www.rfc-editor.org/rfc/rfc6376) selector of maddy. The records of the organisation domain stay with the system that serves human mail. [`DMARC`](https://www.rfc-editor.org/rfc/rfc7489) is published once at the organisation domain and governs the subdomain through `sp=`. So both senders report into one place. All records are committed with the other DNS of the environment, per [ADR-0200](0200-cluster-topology.md). They start at `p=none` with reporting, and move to `p=reject` once reports are clean |
| Signing key | the DKIM private key is SOPS-encrypted, per [ADR-0202](0202-secrets.md) |
| Transport security | delivery honours [DANE](https://www.rfc-editor.org/rfc/rfc7672) `TLSA` records and [MTA-STS](https://www.rfc-editor.org/rfc/rfc8461) policies where a receiver publishes either. It falls back to opportunistic STARTTLS where the receiver publishes neither. If the published policy of a receiver fails to validate, the delivery is deferred, never sent in cleartext |
| Senders | Kratos, per [ADR-0304](0304-identity-and-authorization.md), and services, both through SMTP submission. No service embeds a provider SDK. Mail that a recipient did not trigger individually carries one-click [`List-Unsubscribe`](https://www.rfc-editor.org/rfc/rfc8058). Transactional mail does not, and the bulk-sender rules of the major receivers exempt it |
| Retries | delivery is a Temporal activity where it must be tracked. It is the outbox where fire-and-forget is honest, per [ADR-0302](0302-temporal.md) |
| Human mailboxes | not a platform concern, and never the same sender as platform mail. Bought or self-hosted, they serve the `MX` of the domain from their own egress IP and `DKIM` selector, independent of maddy |
| Local and non-prod | **Mailpit** as a sink. It has no outbound delivery path. So the never-deliver rule of non-production is a property of the component, not a setting on it. Its viewer is an ops origin, per [ADR-0306](0306-trust-tiers-and-urls.md), gated on the same operator session as every other one |
| Delivery observability | every send is a Temporal activity or an outbox row. So a submission failure is a failed activity with a retry history. Rejections after submission arrive as DMARC aggregate reports. The logs of the agent are scraped like the logs of any other component, per [ADR-0500](0500-observability.md). The signal that matters is the completion rate of the identity flow. A verification mail that never lands shows up as a drop there, before a support ticket |

**Every sender speaks SMTP.** This single rule makes the exit below a configuration change. No service imports a provider client, so the relay target is a host, a port, and a credential. Parity also holds here, per [ADR-0205](0205-environment-parity.md). The submission seam is identical in every environment. Only deliverability differs, and it has no local equivalent.

### Platform mail and human mail are never the same sender

Both can be self-hosted. They are still two senders, because a merge degrades the identity path in three ways:

- **Reputation.** A compromised staff mailbox that sends spam for an afternoon degrades the IP that delivers password resets. A forwarded newsletter that draws complaints does the same. Account recovery has no fallback, and staff mail does.
- **Availability.** Once the suite also carries platform mail, a suite upgrade, a full mailbox store, or a webmail CVE becomes an identity incident.
- **Exit.** [ADR-0000](0000-platform-foundations.md) ranks platform sending first to concede. If it is coupled to a mailbox system, the exit means taking apart a live correspondence system, not a change of three values.

The separation counts only if it is physical:

| Axis | Platform mail | Human mail |
| --- | --- | --- |
| Sender | maddy | the mailbox system |
| Egress IP | dedicated, with its own `PTR` | its own, never shared with platform mail |
| Envelope domain | `mail.example.com` | `example.com` |
| DKIM selector | its own | its own |
| `MX` | none: it only sends | points here |

A shared egress IP or signing domain loses the whole reputation argument. Some deployments cannot give platform mail its own IP. There, maddy beside a suite buys nothing. The suite sends, and the coupling is recorded as accepted, not discovered later.

### If mailboxes are self-hosted

This is out of scope as a platform component. But the choice interacts enough with [ADR-0200](0200-cluster-topology.md) to be worth a ranking. The options table above rejects these suites as *platform senders*. This table ranks them for a different job: to host correspondence.

| Suite | Shape | Runs in-cluster | Verdict |
| --- | --- | --- | --- |
| **Stalwart** | one Rust binary: SMTP, IMAP, JMAP, spam filtering, admin UI. No external datastore required | yes, one deployment and a volume | **Preferred.** The only candidate whose operational shape matches the rest of the platform. It is young against the Dovecot lineage, and that is the price |
| **Mailu** | a container suite: Postfix, Dovecot, Rspamd, Roundcube, admin. It has an official Helm chart | yes | The conservative pick: proven components that deploy in-cluster. It costs several workloads and a datastore, where Stalwart costs one |
| **Mailcow** | about 15 containers, Docker Compose only. Upstream explicitly does not support Kubernetes | no | The best admin experience and the deepest community of the four, but it wants a dedicated VM. Choose it only if that machine is accepted as infrastructure outside the cluster |
| **poste.io** | one container, with a proprietary core and the useful features behind a paid tier | yes | Rejected. To self-host a closed-source blob defeats the reason for self-hosting |

### The exit is pre-built, not deferred

[ADR-0000](0000-platform-foundations.md) ranks this component first to concede. So the seam exists on day one, and nobody designs it under pressure.

| Field | Value |
| --- | --- |
| **Trigger** | one of two events. The first is a sustained delivery-failure or complaint rate against a major receiver that DMARC alignment and IP warmup do not resolve. The second is a listing on a mainstream blocklist that is not cleared within one business day |
| **Seam** | ✓ the relay host, port, and credential are values-file fields. A switch to a managed provider changes those three and the SPF record. No code changes |
| **Cost if adopted late** | a population of locked-out users and support load while the reputation is rebuilt. This is why the trigger is a measured rate, not a judgement call |

## Consequences

### Positive

- Identity flows have a production delivery path that the platform owns end to end. Recipient addresses stay on controlled infrastructure.
- One Go binary and no datastore, against a floor that is the budget.
- The SMTP-only rule makes the sanctioned exit a values change. So the concession that ADR-0000 expects is cheap when it happens.

### Negative and Risks

- **Deliverability is a standing operational duty**, not a deploy. IP warmup, DMARC report review, and blocklist monitoring are recurring work for a small platform team. [ADR-0000](0000-platform-foundations.md) names this cost as irreducible. It is accepted, not mitigated.
- **A blocked port 25 makes self-hosting impossible on some providers.** Verify egress before provisioning, because the failure appears at the first send, not at deploy.
- **`PTR` delegation is a provider capability, not a given.** The dedicated egress IP needs reverse DNS that resolves to the HELO name of maddy. Providers vary. Some offer it, some offer it only on a support request, and some never offer it for load-balancer addresses. Receivers treat a missing or mismatched `PTR` as a strong negative signal. So this fails in the same way as blocked egress: at the first send. Provider selection confirms it, per [ADR-0200](0200-cluster-topology.md).
- **Two senders means two reputations to keep.** Where mailboxes are self-hosted, the separation that this ADR mandates costs a second static IP, a second warmup, and a second set of blocklist checks. A coupling is worse, because it puts account recovery behind the complaint rate of staff mail. But the cost is real, and it lands on the same small team.
- **A reputation incident is slow to reverse.** The trigger above exists so that the swap happens on a measurement, not after a month of silent failures.
- **A broken MTA-STS or DANE policy at a receiver delays our mail and does not deliver it.** This is accepted deliberately. An identity mail that arrives late is recoverable. One that crosses the internet in cleartext is not. The delay is visible as a retrying activity, so it shows up as a metric, not as a silent hold.
- **Mail is a side channel that third parties can observe.** Its content is minimal by construction: links and codes, never personal data, per [ADR-0301](0301-data-lifecycle-privacy.md).

## Rules

- Outbound mail leaves through a self-hosted maddy submission endpoint on a dedicated IP with a matching `PTR` record.
- The platform sends mail and does not receive it. No inbound listener, mailbox, or IMAP surface is deployed *as part of the platform*. A mailbox system, if one exists, is separate infrastructure.
- Every sender speaks SMTP. No service embeds an email-provider SDK, so the relay target stays a configuration value.
- Platform mail and human mailboxes are never the same sender. They use separate egress IPs and separate `DKIM` selectors, whether the mailbox system is bought or self-hosted. Platform mail sends as a subdomain.
- `SPF`, `DKIM`, and `DMARC` are committed per environment. DMARC reaches `p=reject` before an environment is treated as production. `(ref: RFC 7208, RFC 6376, RFC 7489)`
- Delivery honours DANE and MTA-STS where the receiver publishes them. A failed policy validation defers the message. It never downgrades to cleartext. `(ref: RFC 7672, RFC 8461)`
- Non-production environments deliver to a sink, never to a real recipient. The sink has no outbound delivery path, so the production agent does not serve as one.
- Mail that a recipient did not trigger individually carries one-click `List-Unsubscribe`. Verification, recovery, and other transactional mail does not. `(ref: RFC 8058)`
- Mail bodies carry links and codes, never personal data, per [ADR-0301](0301-data-lifecycle-privacy.md).
- Delivery failure is observable as a metric. A failed submission is a failed activity, and a dropped verification mail moves the completion rate of the identity flow.
