# Authorization levels

Companion to [ADR-0010](../adr/0010-auth.md). Explains why every project built from this template uses OpenFGA — one
engine — even the simplest ones, and how a simple project stays simple.

## One engine, three levels

Authorization runs on a single engine (OpenFGA) behind a single seam (`libs/go/authz`'s `Checker`). What grows from a
simple project to a complex one is not the tool, only the schema. Three levels:

- **L1 — role per org** (this *is* flat RBAC). Members and admins of an organisation. ~15 lines of DSL. Most
  instances live here forever.
- **L2 — resource ownership.** `owner` / `editor` / `viewer` relations on individual resources.
- **L3 — sharing and hierarchy.** Groups, folders, inheritance, cross-org sharing.

The `Checker` interface is identical at every level; only `model.fga` grows. **We did choose RBAC — L1 is RBAC — it
just runs on the engine that also does L2 and L3, so nobody ever migrates tools.**

### L1 is RBAC, expressed in OpenFGA

```fga
type user

type organization
  relations
    define admin: [user]
    define member: [user]
    define view: admin or member
    define manage: admin
```

That is flat RBAC. Nobody learns graph theory to use it. Role-shaped usage keeps the tuple set tiny (membership changes
only, already an `orgs`-service operation), so the dual-write surface scales down with it.

## Why ReBAC everywhere, not "RBAC first, migrate later"

The template spawns many products; only some need ReBAC. It is tempting to ship flat RBAC and migrate later. We do not,
because the switching cost is not one number but three, and they differ sharply:

1. **Check sites** — the `Checker.Allowed(ctx, action, resource)` calls — are ~free to switch. [ADR-0010](../adr/0010-auth.md)
   already mandates this as the sole authz seam and forbids inline `user.role ==` checks. Already bought.
2. **Data model** — hard, and the cost grows with accumulated data. RBAC stores subject→role; ReBAC stores
   subject→relation→object tuples. Switching means backfilling a tuple per existing relationship — trivial if you only
   stored "alice is org-admin," brutal once you grew per-resource ACL tables.
3. **Dual-write discipline** — hard and invasive. RBAC-in-Postgres is one transaction; ReBAC keeps two stores in sync
   (the Temporal dual-write, [ADR-0006](../adr/0006-temporal.md) / [ADR-0010](../adr/0010-auth.md)). Retrofitting that
   into every authz-relevant mutation path late is the genuinely nasty part.

The deciding twist: RBAC answers a **subject-shaped** question ("what role has this user?"); ReBAC also answers an
**object-shaped** one ("can this user act on *this specific* resource?" — sharing, per-resource roles, cross-org
ownership). So:

- A role-shaped product **never needs to switch** — RBAC serves it forever.
- A per-resource product **cannot be answered by RBAC at all** — it needed ReBAC from the start, not later.
- "Start RBAC, migrate later" therefore only ever serves a population that either never migrates or should never have
  started on RBAC — and the rare true middle case hits the *maximum* accumulated-data cost (#2 + #3). Optimising the
  template for its worst path. Rejected.

## The one honest tax

Even at L1, ReBAC imposes the dual-write habit plus one extra Postgres-backed Go binary (OpenFGA) that pure RBAC-in-DB
would not. This is accepted deliberately, for: one tool, one mental model, the whole team fluent in it, and zero
worst-path migration. Simple instances start at L1 and most stay there — L1 is the first-class default, not a fallback.
