# ADR-0003: Naming and Identifiers

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0001](0001-documentation-and-output-conventions.md), [ADR-0200](0200-cluster-topology.md), [ADR-0202](0202-secrets.md), [ADR-0300](0300-data.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0500](0500-observability.md)
- **Decides:** Every named resource derives from one dash-joined `{project}-{env}-{role}` slug, and every entity identifier is a UUIDv7 carried on the wire with a type prefix.

## Context

**One instance of this repo is one project.** Each project instantiates the template once, so the project name is the identity of everything that the instance owns. A project is operated independently and **may run on any provider**. This scope is wider than [ADR-0200](0200-cluster-topology.md), which documents the default topology and not a provider.

Two families of names run through the platform. Both fail in the same way when taste decides them.

**Resource names** are read by an engineer who switches between projects in one day. They cover compute instances, provider accounts, object-storage buckets, DNS zones, Kubernetes contexts and namespaces, node hostnames, and SSH host aliases. They also cover `age` recipients in `.sops.yaml`, per [ADR-0202](0202-secrets.md).

**Entity identifiers** are the values that a service assigns to its own rows and gives to callers. They cover primary keys, the ID in a URL path, the value in a support ticket, and the key that makes a retry safe.

| Failure | Consequence |
| --- | --- |
| A name in our files does not match the name in the provider's console | An engineer cannot grep across the boundary, and works on the wrong resource |
| Two projects collide | `prod-db` means nothing once more than one project exists |
| Two surfaces spell the same environment differently | Every join between them needs a translation, and one of them is stale |
| An identifier does not say what it identifies | A value in a log or a ticket cannot be traced, and an argument of the wrong type compiles |
| The first service that needs an identifier chooses its form | The second service chooses differently, and the two can never share tooling |

This ADR owns the **grammar and charset** of every name that the platform assigns. Some surfaces have a naming decision of their own, and that ADR owns it. This ADR links to it:

- URL paths, per [ADR-0303](0303-api-contracts-and-lifecycle.md)
- hostnames, per [ADR-0306](0306-trust-tiers-and-urls.md)
- task names, per [ADR-0101](0101-monorepo.md)
- metric names, per [ADR-0500](0500-observability.md)
- release tags, per [ADR-0103](0103-release-and-versioning.md)

## Decision drivers

1. **File and console parity.** A name written in the repo is the exact string that the provider's console shows.
2. **Provider agnostic.** The scheme rests on published standards, not on a survey of one set of providers. A project that adopts this template may run anywhere.
3. **The project name is globally unique.** Each project picks a slug that is distinctive enough to stand alone in the global namespace of any provider. So no org prefix is ever needed.
4. **Mechanical, not conditional.** The scheme applies with no judgement call per resource, per principle 5 of [ADR-0000](0000-platform-foundations.md). A vocabulary that this ADR does not close is a vocabulary that the next engineer invents.
5. **Adopt, do not invent**, per [ADR-0001](0001-documentation-and-output-conventions.md). Every charset, cap, and identifier format below is a published standard, or is derived from one in the open.

## Considered options

### Resource names

| Option | File-console parity | Provider agnostic | Verdict |
| --- | --- | --- | --- |
| **One slug on a standards-derived charset, plus one mechanical compact form** | exact | yes: the charset is RFC 1123, not a provider survey | **Chosen** *(reasoned)* |
| One slug on the intersection of a named provider set | exact | no: the intersection changes when the provider set changes, and a template cannot name its provider set | Only a new survey of providers can derive it again, and nobody does that. The cap becomes folklore |
| Per-provider name variants | broken by construction | yes | Every name needs a translation table, and a grep across the boundary fails |
| Org prefix on every name, such as `acme-corp-` | exact | yes | It spends characters of a tight budget on a constant, and the project slug already tells projects apart |
| Descriptive per-resource suffixes on collision, such as `-eu` or `-2` | exact | yes | A meaningful suffix is itself a guess that can collide again. It brings back the per-resource judgement that this ADR removes |
| Generated opaque names: a UUID, or a name the provider assigns | exact | yes | They are unreadable, so a command in the wrong context is invisible. That is the failure this ADR exists to prevent |

### Entity identifiers

The exit cost is months and customer data. An identifier is part of every row, every URL a customer has bookmarked, and every log line ever written. This comparison is the deep one.

| Option | Enumeration exposure | Index behaviour | Type safety | Verdict |
| --- | --- | --- | --- | --- |
| **UUIDv7 stored, type-prefixed on the wire** | none: 74 random bits per value | sequential prefix, so inserts append | the prefix names the type at every boundary | **Chosen.** [RFC 9562](https://www.rfc-editor.org/info/rfc9562/) for the value, and the Stripe and [TypeID](https://github.com/jetify-com/typeid) convention for the surface *(documented)* |
| `bigserial` | total: any single ID leaks the count and the creation order | ideal | none | Two services cannot mint IDs independently. A leaked count is a business fact that we did not choose to publish |
| UUIDv4 | none | random, so every insert lands in a cold page and the B-tree fragments | none | Every table pays the write amplification forever, and v7 removes it at no cost |
| ULID | none | sequential | none | It solves the same problem as v7 outside the RFC. It has no database type, no `uuid` column, and no library in every language |
| Bare UUIDv7, no prefix | none | sequential | none | It loses the whole reason for the surface convention: a bare UUID in a log or a ticket says nothing about what it identifies |
| Separate internal key and public key | none | ideal | partial | Two identifiers per row, a join to translate, and a permanent question about which one a code path holds |

## Decision

### The slug grammar

Every named resource derives from one dash-joined slug:

```text
{project}-{env}-{role}[-{n}]
```

| Segment | Source | Values |
| --- | --- | --- |
| `project` | the globally-unique project slug, fixed at instantiation | `northwind`, `acmeco` |
| `env` | the environment, verbatim from [ADR-0200](0200-cluster-topology.md) | `dev`, `staging`, `prod`, with no abbreviations |
| `role` | one token from the closed table below | `cp`, `node`, `assets` |
| `n` | an ordinal, only where several of a role exist | `1`, `2`, `3` |

The `env` token is the environment's own name and nothing else. It is the same string in the GitOps tree, in the Kubernetes context, and in the OTel `deployment.environment.name` attribute, per [ADR-0500](0500-observability.md). So no surface needs a mapping to another surface.

Worked example for project `northwind`:

| Thing | Name |
| --- | --- |
| Compute instance | `northwind-prod-cp-1` |
| Provider account or project | `northwind-prod` |
| Object-storage bucket | `northwind-prod-assets` |
| Kubernetes context | `northwind-prod` |
| Kubernetes namespace | `northwind-prod`, or service-scoped per the in-cluster rule below |
| SSH host alias | `northwind-prod-cp-1` |
| `age` recipient | `northwind-prod` |

### `role` is a closed vocabulary

A scheme with one free-text field does not satisfy driver 4. `role` takes a value from this table and no other:

| `role` | Names |
| --- | --- |
| `cp` | a Kubernetes control-plane node |
| `node` | a Kubernetes worker node |
| `lb` | a load balancer |
| `net` | a network or VPC |
| `fw` | a firewall or security group |
| `dns` | a DNS zone |
| `assets` | the public object-storage bucket |
| `backup` | the backup object-storage bucket, per [ADR-0207](0207-cluster-storage.md) |
| `state` | the infrastructure-state bucket |

A new resource class adds a row here in the same PR that adds the resource. A token is at most six characters, so the table reads `cp` and not `control-plane`.

### Charset and length, derived and not surveyed

The slug rests on **[RFC 1123](https://www.rfc-editor.org/rfc/rfc1123) DNS labels**. DNS, TLS names, Kubernetes objects, hostnames, and provider APIs all accept this one identifier form. The anchor is a standard, and that meets driver 2. A project on an unfamiliar provider derives the rule again and does not need a new survey.

| Property | Rule | Derivation |
| --- | --- | --- |
| Charset | `^[a-z][a-z0-9]*(-[a-z0-9]+)*$` | An RFC 1123 DNS label: lowercase alphanumerics and interior hyphens. It is narrowed to a leading letter, which [RFC 1035](https://www.rfc-editor.org/rfc/rfc1035) surfaces such as a Kubernetes Service require. The pattern admits no trailing hyphen and no doubled hyphen, and a DNS label rejects both |
| Full slug length | at most 63 characters | Four independent standards land on the same number: an RFC 1123 DNS label, a [Kubernetes object name and label value](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/), and a PostgreSQL identifier at `NAMEDATALEN - 1`, per the [Postgres lexical structure](https://www.postgresql.org/docs/current/sql-syntax-lexical.html) |
| Project slug length | 5 to 11 characters, including any collision token | The compact-form budget below sets the upper bound: `24 - len("staging") - 6`, where 6 is the `role` cap. The lower bound of RFC 1123 is one character. The floor here comes from legibility, not from any namespace. A namespace with a higher floor is a per-provider constraint, priced in *Negative and Risks* |

A slug that passes this rule is reused verbatim in every provider and every file.

### The compact form

Some namespaces reject hyphens and have a shorter cap than a DNS label. The common case is a name of the storage-account class, at 24 characters of lowercase alphanumerics. The slug's **compact form** serves them: the canonical slug with its hyphens removed.

```text
northwind-prod-assets   canonical, used everywhere that accepts a DNS label
northwindprodassets     compact, used only where hyphens are rejected
```

This is one pure function, applied the same way on every provider. It is not the per-provider translation table that *Considered options* rejects. There is nothing to look up, and a reader derives either form from the other by eye.

The project-slug cap makes the compact form always fit in 24 characters. Ordinals are outside that budget. A role that takes an ordinal is a node or an instance, and it never lands in a flattened namespace.

### Names carry identity, labels carry provenance

A name is short because the namespaces it must satisfy are short. Everything that a name cannot hold is attached beside it. Both the [Azure Cloud Adoption Framework](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming) and Kubernetes make this split.

| Fact | Where it lives |
| --- | --- |
| Identity: which resource this is | the slug |
| Application, component, part-of, managed-by | [Kubernetes recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/), `app.kubernetes.io/*`, which [ADR-0201](0201-gitops.md) already applies |
| Project and environment, in telemetry | OTel `service.namespace` and `deployment.environment.name`, per [ADR-0500](0500-observability.md) |
| Anything else: owner, cost centre, ticket | a provider tag, never a name segment |

So a new segment in a name is a last resort. Most provider names are immutable, so nobody can correct the segment later. A label or a tag can change.

### Only constant facts go in a name

A name records what does not change for the life of the resource. This is the rule of the Cloud Adoption Framework. [RFC 1178](https://www.rfc-editor.org/rfc/rfc1178.html) reaches it from the other direction. It lists a machine named after its function among the practices to avoid, because the function moves and the name does not.

`role` is a deliberate departure, and the only one. The role of a Kubernetes node is structural, not functional. A control-plane node does not become a worker, and a machine whose purpose changes is replaced, not renamed. This grammar does not name application workloads, whose placement does move. They are Kubernetes objects that carry `app.kubernetes.io/*` labels.

### In-cluster names drop implied segments

A single cluster holds exactly one project and one environment. So node hostnames and namespaces omit `{project}-{env}`. A node is `cp-1`, and a service namespace is its service name. The labels and resource attributes above hold the dropped segments. They are omitted, not lost.

The full slug is required only where names **cross the cluster boundary**: provider resources, Kubernetes *context* names, SSH aliases, and `age` recipients. The operator already selected the context to be inside the cluster. The project name on every in-cluster object is noise.

### The global-namespace backstop

Object-storage buckets and provider account identifiers live in a namespace that every other customer of that provider shares. Two defences apply, in order.

The first is an **availability check at instantiation**, before anything uses the slug. A well-chosen project slug makes a later collision rare. A collision found at instantiation costs one prompt.

The second defence is mechanical, for a collision that appears anyway. It appends a random `[a-z0-9]{4}` token to the **project segment**, and the result is the project slug everywhere.

```text
northwind       → northwind-prod-assets unavailable in a global namespace
nwind7q2        ← project slug becomes nwind7q2, applied across all resources
```

The token is generated once and recorded as the project slug, inside the budget of 5 to 11 characters. It is not a per-resource suffix. The whole project carries it, so every derived name stays consistent and the grammar does not change. It is random and not descriptive, for the reason in *Considered options*.

### A second cluster in one environment

One environment is one cluster, per [ADR-0200](0200-cluster-topology.md). A second cluster in the same environment, such as a second region or a residency boundary, needs a discriminator. The grammar has no segment for it.

| Field | Value |
| --- | --- |
| **Trigger** | a second cluster provisioned inside one environment |
| **Seam** | yes. The second cluster is its own project with its own slug. The Rules already require this of any infrastructure that is not tied to a single product. No new segment, and no renaming |
| **Cost if adopted late** | nothing structural. The two clusters carry unrelated project slugs. So cross-cluster tooling identifies them by their `service.namespace` attribute, not by a shared prefix |

### SSH keys

| Concern | Rule |
| --- | --- |
| Key pair on a laptop | `~/.ssh/{project}-{env}`, for example `~/.ssh/northwind-prod`. No owner segment: a laptop holds only the key of its own engineer |
| `~/.ssh/config` host alias | the full instance slug, so `ssh northwind-prod-cp-1` works without flags and reads the same as the console |
| Public keys in a shared namespace | add a `{handle}` owner segment: `{project}-{env}-{handle}`, for example `northwind-prod-alice` |
| Public key comment | `{project}-{env}-{handle} {date}` |
| Rotation | edit the per-project authorized keys and run the provisioning play again, per [ADR-0200](0200-cluster-topology.md) |

The shared namespaces are the host's `authorized_keys`, a provider's named SSH-key resource, and the per-engineer `age` recipients of [ADR-0202](0202-secrets.md). Without the handle, every engineer's key reads as `{project}-{env}` in the one place where the keys sit together. No key then traces to a person, and the revocation of the right key becomes guesswork. `handle` is a short, stable, lowercase token per engineer that obeys the same charset rule.

### Entity identifiers

**Every row's primary key is a UUIDv7**, standardised in [RFC 9562](https://www.rfc-editor.org/info/rfc9562/). It is stored in a Postgres `uuid` column and generated in application code. So a service knows the identifier before the insert, and it does not depend on a database version for the generator.

**Every identifier that crosses a service boundary is type-prefixed**, in the [TypeID](https://github.com/jetify-com/typeid) form:

```text
order_01j8xk7m3q0000000000000000
{prefix}_{UUIDv7 in 26 characters of base32}
```

| Property | Rule |
| --- | --- |
| Prefix | the singular `snake_case` form of the resource's collection noun in [ADR-0303](0303-api-contracts-and-lifecycle.md). `/orders` yields `order_` |
| Where the prefixed form appears | request and response bodies, URL path parameters, logs, telemetry attributes, and error messages |
| Where the bare UUID appears | the `uuid` column, and nowhere else |
| Conversion | at the transport boundary, by one library per language, per [ADR-0100](0100-language-and-runtime.md) |
| Client treatment | opaque. A consumer never parses, orders, or constructs an identifier, per [AIP-122](https://google.aip.dev/122) |

The prefix gives three benefits:

- a value in a support ticket says what it is
- a log line is greppable by type
- a generated client cannot pass an `order_` where a `product_` belongs

**An unguessable identifier is not an authorisation control.** [OWASP](https://cheatsheetseries.owasp.org/cheatsheets/Insecure_Direct_Object_Reference_Prevention_Cheat_Sheet.html) states that a random identifier slows enumeration and prevents nothing else. [ADR-0304](0304-identity-and-authorization.md) authorises every read and every mutation as though the identifier were public, because it is public.

### Identifiers that are not entity identifiers

People often confuse three values with an entity ID. Each one has one owner and one standard.

| Value | Form | Owner |
| --- | --- | --- |
| Correlation across services | the W3C [Trace Context](https://www.w3.org/TR/trace-context/) `traceparent`. No `X-Request-Id` is minted | [ADR-0500](0500-observability.md) |
| Client-supplied retry deduplication | the `Idempotency-Key` request header with a random value that the client generates, per [draft-ietf-httpapi-idempotency-key-header](https://datatracker.ietf.org/doc/html/draft-ietf-httpapi-idempotency-key-header-07) | here |
| Server-side execution deduplication | the Temporal Workflow ID, derived from the business key and not from the `Idempotency-Key` | [ADR-0302](0302-temporal.md) |

The last two are not alternatives. The header deduplicates a retried HTTP request at the edge of the service. The Workflow ID deduplicates the business operation, however the request reached it.

### Casing by surface

One table covers every surface, so no surface depends on precedent. Where another ADR owns the naming decision, this row states the casing and that ADR states the rule.

| Surface | Form | Owner |
| --- | --- | --- |
| Provider resources, contexts, SSH aliases, `age` recipients | the slug grammar above | here |
| Kubernetes object names | RFC 1123 DNS label. RFC 1035 where the object requires a leading letter | here |
| Repository directories | `kebab-case` | here |
| SQL tables and columns | `snake_case`, with plural tables and singular columns. Identifiers stay under 63 bytes | here, applied by [ADR-0300](0300-data.md) |
| JSON request and response fields | `snake_case`, noun-shaped, plural where repeated, per [AIP-140](https://google.aip.dev/140) | here |
| OpenAPI schema names | `PascalCase`. `operationId` is `camelCase` | [ADR-0303](0303-api-contracts-and-lifecycle.md) |
| URL paths | plural resource nouns, no version segment | [ADR-0303](0303-api-contracts-and-lifecycle.md) |
| Hostnames | `{tool}.ops.<host>` and the trust-tier scheme | [ADR-0306](0306-trust-tiers-and-urls.md) |
| Environment variables | `SCREAMING_SNAKE_CASE` | here |
| Go and TypeScript identifiers | the language's own convention | [ADR-0001](0001-documentation-and-output-conventions.md) |
| `mise` tasks | `group:member` | [ADR-0101](0101-monorepo.md) |
| Metrics | OTel semantic conventions, else `<service>_<noun>_<unit>_<type>` | [ADR-0500](0500-observability.md) |
| Git tags, image tags, commit scopes | CalVer and the component path slug | [ADR-0103](0103-release-and-versioning.md) |

## Consequences

### Positive

- A name copied from a provider's console greps cleanly against the repo, and a name from the repo greps cleanly against the console.
- A switch between projects is safe. Every name starts with the project, so a command in the wrong context is easy to see.
- The charset and the caps come from published standards. So a project on a provider that nobody here has used derives them again and does not guess.
- One environment token spans the GitOps tree, the Kubernetes context, and telemetry, so no join between them needs a mapping.
- A closed `role` table and a single compact-form transform remove two things: the per-resource naming debate and the per-provider translation table.
- A prefixed identifier describes itself in a log, a ticket, and a function signature. UUIDv7 keeps the primary-key index in append order.

### Negative and Risks

- **The 24-character compact-form budget limits the project slug to 11 characters**, even for projects that never touch a namespace that short. Accepted: the alternative is to discover the constraint after the names are immutable.
- The six-character `role` cap forces short tokens. The table is closed and lives in this ADR, not in a glossary elsewhere, and that mitigates the cost.
- A long project name uses up the budget. A project whose natural name exceeds it picks a documented short slug at instantiation.
- **Some globally-namespaced identifiers reject a slug below six characters.** [Google Cloud project IDs](https://cloud.google.com/resource-manager/docs/creating-managing-projects) start at 6. Accepted: the floor is a legibility rule, not a portability rule. A project that meets such a namespace spends the collision token on it, and that adds four characters. A rule built on the minimum of one provider is the surveyed cap that this ADR rejects in *Considered options*.
- The project slug carries the whole uniqueness guarantee. The random-token backstop covers a true provider-global collision at the cost of readability. So it is a fallback, not the default.
- **Prefixed identifiers change every API surface.** A spec's `type: string, format: uuid` becomes a string with a pattern constraint, and the generated clients change with it. The encode and decode step is one library per language, and every boundary crossing pays for it.
- The database stores the bare UUID and the API serves the prefixed form, so the two differ in a `psql` session. Accepted: the alternative is a `text` primary key. It costs more on every index than the conversion costs on every request.

## Rules

### Resource names

- Every named resource derives from `{project}-{env}-{role}[-{n}]`. Shared infrastructure that is not tied to a product is its own project with its own slug, and follows the same grammar. Examples are a team proxy, an internal forge, and a registry mirror.
- A slug matches `^[a-z][a-z0-9]*(-[a-z0-9]+)*$` and is at most 63 characters. `(CI: lint:naming)`
- The project slug is 5 to 11 characters, including any collision token. It is globally unique and stands alone. No org prefix or cross-project prefix is added before it. `(CI: lint:naming)`
- `env` is `dev`, `staging`, or `prod`, spelled the same way in every surface. Abbreviated forms are not used. `(CI: lint:naming)`
- `role` is a token from the table in this ADR. A new resource class adds a row in the same PR. `(CI: lint:naming)`
- The same string is used in files and in the console of every provider. Where a namespace rejects hyphens, the compact form is used: the slug with its hyphens removed. No other transformation is applied.
- A name records only facts that are constant for the life of the resource. Owner, cost centre, and application metadata are Kubernetes labels, OTel resource attributes, or provider tags.
- A true provider-global collision is resolved with a random `[a-z0-9]{4}` token appended to the project slug, never with a descriptive or per-resource suffix. `(CI: lint:naming)`
- The full slug is required where names cross the cluster boundary: provider resources, Kubernetes contexts, SSH aliases, and `age` recipients. In-cluster hostnames and namespaces drop the implied `{project}-{env}`.
- SSH key pairs are named `{project}-{env}` on an engineer's laptop. Where the public keys of several engineers share a namespace, each key carries a `{handle}` owner segment.

### Identifiers

- A primary key is a UUIDv7 in a Postgres `uuid` column, generated in application code. Sequential integer keys and UUIDv4 are not used. `(ref: RFC 9562)`
- An identifier that crosses a service boundary is type-prefixed as `{prefix}_{base32 UUIDv7}`. `prefix` is the singular form of the resource's collection noun. The bare UUID appears only in the database. `(ref: RFC 9562)`
- An identifier is opaque to its consumer. No client parses, orders, or constructs one.
- An unguessable identifier is never treated as an access control. Every access is authorised per [ADR-0304](0304-identity-and-authorization.md).
- Cross-service correlation uses the W3C `traceparent`. No service mints its own request identifier. `(ref: W3C Trace Context)`
- Client retry deduplication uses the `Idempotency-Key` request header. It is not reused as a Temporal Workflow ID.

### Casing

- Every surface uses the casing in the *Casing by surface* table. A surface that is absent from that table is added to it before it is used.
- JSON request and response fields are `snake_case` nouns, plural where repeated.
- SQL tables are plural `snake_case`, columns are singular `snake_case`, and every identifier stays under 63 bytes. `(CI: lint:sql)`
- Environment variables are `SCREAMING_SNAKE_CASE`.
