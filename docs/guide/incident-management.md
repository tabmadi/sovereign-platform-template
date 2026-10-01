# Incident Management

[`break-glass.md`](break-glass.md) covers access when the auth plane is down. This document covers the process. It defines an incident, the roles, and the work that follows an incident.

On this platform, **nothing pages**, per [ADR-0502](../adr/0502-alerting-and-on-call.md). The severities below are designed for that limit. They do not leave paging out by mistake. This platform cannot honour a severity that expects someone to wake up. [`detection-latency`](../reference/detection-latency.md) states what the platform can honour.

## Severity

Severity measures **user-visible impact**, never how serious the cause looks. A full queue that affects nobody is not an incident. A checkout that fails for one organisation is an incident.

| Sev | Test | Response | Real detection time |
| --- | --- | --- | --- |
| **1** | Users cannot complete a core operation, or data integrity is at risk | stop other work. One responder and one comms owner | minutes during working hours. Outside working hours, the next working day. This is the true figure, and it is the reason Sev 1 has an escalation trigger |
| **2** | A core operation is degraded, or a non-core one fails. A workaround exists | the same working day | as above |
| **3** | A contained fault with no user impact. Examples: a failing job, a stuck reconcile, a component in a bad state | the next working day | as above |
| **4** | Something that becomes an incident if nobody acts. Examples: a certificate near expiry, a volume near a threshold, a backup that failed once | this week | usually an alert, and not urgent yet |

**Set the severity at declaration, and change it when you need to.** The first assessment has the least information of any. A change up is not an admission of error. A change down closes an incident that a signal reported wrongly.

## Roles

At this team size, a role is a task, not a person. One person can hold two roles. One person must not hold all three and drop the third.

| Role | Owns | The failure it prevents |
| --- | --- | --- |
| **Responder** | the technical work: diagnosis, mitigation, the fix | none |
| **Comms** | who is told, and when. This covers anyone affected, anyone who can ask, and the record as it grows | an incident that is resolved, and nobody outside it knows |
| **Scribe** | the timeline: what was observed, what was tried, what changed, with times | a timeline written from memory afterwards, which loses the useful detail |

For Sev 3 and 4, one person holds all three roles. The scribe's work is a few lines in the issue.

## The sequence

1. **Declare.** Open an issue in the forge, per [ADR-0102](../adr/0102-source-control-and-ci.md). Give the severity and one sentence of user-visible impact. An early declaration that you later close costs little. A late declaration costs more.
2. **Mitigate before you diagnose.** Service recovery and cause analysis are different jobs, and the first comes first. A rollback is a mitigation, per [ADR-0201](../adr/0201-gitops.md). Disabling a feature or shedding load are mitigations too.
3. **Diagnose from the funnel.** The three dashboard levels answer in order, per [ADR-0501](../adr/0501-operator-uis-and-dashboards.md):
   - what is wrong
   - which service
   - what the service is doing
4. **Use the operational surface.** If a component is the suspect, read the *What stops working* column of [`../operational-surface.md`](../operational-surface.md). It lists what must already be broken. This confirms or removes the suspect faster than a dashboard.
5. **Record as you go.** Write times, observations, and actions in the issue. The scribe writes what the responder says out loud.
6. **Resolve.** Then report the resolution to everyone who heard about the incident.
7. **Review**, per the threshold below.

## Postmortems

**Write a postmortem for every Sev 1, every Sev 2 that recurs, and any incident that someone asks to review.** Sev 3 and 4 close with their issue.

A postmortem is blameless in the operational sense. Its subject is the system that let a correct-looking action have that effect. This platform cannot change a person's judgement in the moment, but it can change the system.

| Section | Contains |
| --- | --- |
| Impact | who was affected, in what way, and for how long |
| Timeline | first occurrence, first detection, mitigation, resolution. The gap between the first two is the detection latency that this platform delivered |
| Cause | the conditions that made the failure possible, not the last change before it |
| What worked | the controls that caught the failure or limited it. These teach as much as the controls that failed |
| Actions | each action has an owner and a home: a rule in an ADR, a check in CI, an alert, or a runbook entry |

**An action item without a home is not an action item.** These are the homes:

- a rule in the owning ADR
- a check in `mise run lint`
- an alert rule
- a row in [`deferral-register`](../reference/deferral-register.md)
- a runbook under `docs/guide/`

Nobody reads a postmortem again, so an action that lives only there is lost.

**Two incident counts feed decisions that are already recorded:**

- Session replay has a trigger: three separate incidents in one quarter where traces and RUM logs cannot reproduce a reported bug. See [ADR-0700](../adr/0700-analytics.md).
- A second non-determinism failure in production triggers versioning, per [ADR-0302](../adr/0302-temporal.md).

Both counts come from these records. So an incident that nobody writes down is a trigger that never fires.

## What this platform does not have

This section states the gaps directly. A process document that claims capabilities it lacks is worse than no document.

- **No rota and no pager.** Outside working hours, detection is the next working day, for every severity, per [ADR-0502](../adr/0502-alerting-and-on-call.md).
- **No incident-management tooling.** The forge's issues are the record. No second place tracks work, per [ADR-0503](../adr/0503-error-tracking.md).
- **No status page.** Comms contacts the known affected parties directly. A public status page is a product decision that each project makes for itself.
