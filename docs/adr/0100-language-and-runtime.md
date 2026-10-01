# ADR-0100: Language and Runtime

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0101](0101-monorepo.md), [ADR-0104](0104-supply-chain-security.md), [ADR-0204](0204-resource-management.md), [ADR-0302](0302-temporal.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0400](0400-frontend.md), [ADR-0401](0401-internal-admin.md), [ADR-0500](0500-observability.md), [ADR-0600](0600-local-development-loop.md), [ADR-0601](0601-testing-strategy.md)
- **Decides:** Go is the backend language and TypeScript the frontend one, with no third general-purpose runtime and no ambient dependency.

## Context

The axis position set by [ADR-0000](0000-platform-foundations.md) decides this. That position is: decomposition pressure high, operational sovereignty maximal, correctness stakes high. The product domain does not decide it. Two systems at the same axis position get the same answer here, whatever they sell. Two systems in the same market often sit at opposite ends of every axis.

This ADR picks three things:

- the **primary backend language**
- the **conditions under which a second language is admitted**
- the **language and runtime of the frontend**

[ADR-0400](0400-frontend.md) picks the frontend framework.

## Decision drivers

1. **The hiring intersection at this axis position.** Axis B at maximum needs one organisation to staff two roles: writing product services, and operating self-hosted Kubernetes. This is principle 3 of [ADR-0000](0000-platform-foundations.md). The cost of a language is the overlap between those two pools. That overlap is capacity, which is the binding constraint of principle 3. The operated stack is the output of one language, and its operators concentrate there. Readability in the product's language follows from this. It is a benefit, not a second reason.
2. **Per-service cost against a fixed platform budget.** Axis A is high. Each service and each replica pays for the runtime, toolchain, base image, CI cache, and lint configuration. A cost that is acceptable once is not acceptable across a fleet.
3. **Correctness affordances at axis C high.** These are exact arithmetic, predictable concurrency, and types that refuse to represent an invalid state.
4. **A floor under the two SDKs every service links.** Every service is a durable-execution worker, per [ADR-0302](0302-temporal.md). Every service is also a telemetry producer, per [ADR-0500](0500-observability.md). Community-maintained or pre-GA bindings put a load-bearing path in the hands of one maintainer. **This driver admits or excludes a language. It does not rank the languages that pass it.**
5. **One language by default.** A second general-purpose backend language doubles the toolchain, codegen pipeline, CI cache, base image, lint configuration, and review pool. Only a capability that the primary language cannot give justifies it. Preference does not.

## Considered options

| Option | Overlap with the operated stack | Axis C affordances | SDK floor | Verdict |
| --- | --- | --- | --- | --- |
| **Go** | **the stack itself:** Kubernetes and its controller ecosystem, ArgoCD, Traefik, Ory, Temporal's server, the OTel Collector, Prometheus, Loki, and Tempo | static types and CSP concurrency. **No decimal type in the standard library**, and no sum types | passes it, as four others do. Its OTel log signal is beta. The .NET and Java log signals are stable | **Chosen** on drivers 1 and 5. Verbose error handling and a thin type system are accepted. A section below closes the arithmetic gap *(reasoned)* |
| Rust | no | the strongest on offer: exhaustive matching, and no data races by construction. [`sqlx`](https://github.com/launchbadge/sqlx) checks every query against the live schema at compile time. `sqlc` infers it | **fails it.** Temporal is [first-party at public preview](https://temporal.io/changelog/rust-sdk-public-preview), not GA. [OTel Rust](https://opentelemetry.io/docs/languages/) is beta on all three signals | Best correctness in the field. Driver 4 is unmet, and each service pays the velocity cost. **Kept as an escape hatch** |
| .NET with C# | no. Its cloud-native segment is shaped by Azure: managed Kubernetes and hosted CI. That is axis B *low* | native 128-bit `decimal`, records, and pattern matching. This is stronger than Go | passes it. [OTel .NET](https://opentelemetry.io/docs/languages/) is stable across all three signals | **The strongest alternative. It loses on driver 1 alone.** It is better than Go on driver 3, as a section below admits. An engineer who writes C# services *and* has operated self-hosted Kubernetes on hardware is rare. The Azure-native engineer is common, and belongs to a different axis position |
| JVM with Java or Kotlin | no | `BigDecimal`. Kotlin adds sealed hierarchies and null tracking | passes it, on the most mature durable-execution SDK in the field | The same as .NET. It also needs a build tool and an application framework that this ADR must choose. Native compilation is a second build mode under its own licence |
| TypeScript on Bun | no | discriminated unions have the best ergonomics here. Types are erased at runtime, and numbers are IEEE-754 doubles | passes it | The appeal is one language across the stack. A single-threaded event loop and erased runtime types are the wrong default at axis C high. **Kept for the frontend**, where it is unavoidable |
| Python | no | native `decimal`. Annotations are not enforced at runtime | passes it | **Kept as an escape hatch** where the library ecosystem is the reason the service exists |
| Elixir on BEAM | no | supervision trees and true process isolation. Dynamically typed | **fails it:** no first-party durable-execution SDK | Temporal and Kubernetes already give most of its fault-tolerance model here. The platform then pays for that property twice |
| Polyglot by team choice | mixed | mixed | mixed | The honest baseline. At axis A high, the per-language cost multiplies by the number of teams, not by services. Every shared library is written once per language |

**Runtime footprint no longer separates the compiled options.** [.NET Native AOT](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/) and GraalVM native images put C# and Java in the same order of magnitude as a Go binary. This holds at idle and at startup. A decision on resident memory was once decisive and is not now, so drivers 1 and 3 carry the decision.

### The frontend language

The browser runs JavaScript, so the question is which language compiles to it.

| Option | Type system | Ecosystem for the decided frontend | Verdict |
| --- | --- | --- | --- |
| **TypeScript** | structural, and erased at runtime | native. The framework and design system of [ADR-0400](0400-frontend.md) publish their own types. The generated client of [ADR-0303](0303-api-contracts-and-lifecycle.md) does too | **Chosen.** It is the type layer that this field publishes against, so no binding is written here |
| JavaScript | none | native | The contract types of the generated client become comments. Those types are the one reason to generate a client |
| ReScript | sound, and its own | a binding per library, written and maintained here | A stronger type system, paid for per dependency. Most of this frontend is other people's code |
| Elm | sound, and its own | none. Interop goes through ports | A different runtime model. The component library of [ADR-0400](0400-frontend.md) sits on React interop, which is weak in Elm |

## Decision

| Concern | Decision |
| --- | --- |
| Primary backend language | **Go**, latest stable major |
| Frontend language | **TypeScript** |
| JS runtime for code we author | **Bun**, alone: install, workspaces, test, build, and the production server |
| Escape hatch: Rust | a measured CPU or latency requirement that Go does not meet, or a domain whose canonical implementation exists only in Rust |
| Escape hatch: Python | the library ecosystem is the reason the service exists, and the service is a thin wrapper over it |
| A second general-purpose backend language | not adopted |

### Go is chosen for who can staff it

At axis B maximal, the scarce role is not a general backend engineer. It is an engineer who writes product services and can also debug one of these:

- a reconciliation loop
- an admission webhook
- an eBPF datapath
- a collector pipeline

That second capability is the harder hire in any language. Choosing the language of the operated stack does not make it easier. It makes the two pools adjacent. A service engineer can then grow into platform work, and a platform engineer can review service code.

**The claim is about a labour market, so it decays.** It holds while cloud-native infrastructure stays the output of one language and the operators concentrate there. The re-derivation test asks one thing: are engineers who have operated self-hosted Kubernetes still found mostly in roles next to this language. A language-popularity ranking does not answer that test. It is not evidence for this driver.

Two limits bound the claim:

- The strongest platform engineers often do not identify by language. They present as Platform Engineer, SRE, or DevOps. So the overlap is smaller than the language share of the ecosystem suggests.
- Within the same language, a search for infrastructure depth takes longer than a search for API work. This driver reduces that cost. It does not remove it.

**The driver does not weaken as other runtimes improve.** It describes where people are, not what a runtime does. It flips at a different axis position. A platform at axis B low operates none of that stack and needs no overlap. It decides on driver 3, where C# or Kotlin wins.

### Where Go is weak, and what carries the weight

Three gaps are real at axis C high. The language closes none of them.

| Gap | What it costs | What carries the weight |
| --- | --- | --- |
| No decimal type in the standard library | a `float64` monetary amount compiles, and later shows as a rounding discrepancy | one shared money type in `libs/go/money/`, over `math/big` in the standard library. A monetary value is that type at rest, in the contract, and on the wire |
| No sum types, so an invalid state is representable | an illegal state transition compiles | state that must not go invalid is a workflow, where Temporal owns the transitions, per [ADR-0302](0302-temporal.md) |
| Errors are unchecked values | an ignored error compiles | `errcheck` in `golangci-lint` |

`math/big` gives the arithmetic. It gives none of the four properties that make money correct:

- a currency that cannot be added to another currency
- a rounding mode that is chosen, not inherited
- a mapping to a `numeric` column
- a **string** JSON form

A JSON number is an IEEE-754 double by the time a TypeScript client reads it. So the wire form is a string, whatever the Go type is. Those four properties are the type. The arithmetic comes from the standard library, and no third-party decimal package is added.

The platform does not claim that Go is the strongest tool for driver 3. C# and Kotlin are. Driver 1 still ranks above them. The gaps of driver 3 have the mitigations in the table above. The gaps of driver 1 have none, because no library widens a hiring pool.

### What would change this decision

Driver 1 rests on a stack that this ADR does not choose, and on a labour market that it does not control. Driver 4 is a floor, not a ranking. Neither driver is a vote for the tools it names.

| Change | Effect |
| --- | --- |
| The workflow engine is replaced | **None.** It is one dependency inside a service, and the floor screens its replacement in the same way |
| The observability stack is replaced | **None.** Instrumentation is vendor-neutral by the own driver of [ADR-0500](0500-observability.md), and the backends sit behind it |
| The identity stack or the edge proxy is replaced | **None.** Both have credible equivalents in other languages. Those were rejected on configuration-as-code and licence grounds, not on language |
| The position on axis B moves down | **Decisive.** The operated stack goes away, and the roles no longer need to overlap. Driver 1 disappears, and driver 3 decides instead |
| The operator population stops concentrating in one language | **Decisive.** Driver 1 is stated against this condition. Re-derive it with the test in *Go is chosen for who can staff it* above |

The orchestration and controller layer makes driver 1 robust, not incidental. Identity could have been a JVM product, and so could the telemetry stores. Those substitutions leave the decision intact.

At axis B maximal, no orchestrator outside Go is a real option. The custom controllers and the patches are written in that layer. That layer fixes where the operators are, not a count of projects.

### The JS runtime

| Option | Node API compatibility | Toolchain components | Verdict |
| --- | --- | --- | --- |
| **Bun** | **the highest of the three** | **one binary:** runtime, package manager, workspaces, test runner, and bundler | **Chosen.** Driver 2 applied to the toolchain itself *(reasoned)* |
| Node.js | the definition of it | a package manager, a test runner, and a bundler, each selected, pinned, cached, and upgraded separately | Loses on driver 2. Each addition is a version to pin and a supply-chain edge, per [ADR-0104](0104-supply-chain-security.md) |
| Deno | lowest, reached through an `npm:` specifier | comparable to Bun | A second permissions model and a second registry, for no capability this platform needs |

The vendor of the frontend framework ships first-party Bun support. The self-hosting documentation of the framework does not cover the runtime, as [vercel/next.js#55272](https://github.com/vercel/next.js/discussions/55272) shows. End-to-end tests against the built image cover that gap, per [ADR-0601](0601-testing-strategy.md). Upstream documentation does not.

### The three Node islands

Node runs vendored third-party tools. It never runs code we author, and it is never a backend runtime. There are exactly three islands, and none is in the root toolchain. So an engineer who touches none of them never installs Node. The islands are the price of the Bun decision, listed here so that nobody has to find them.

| Island | Why Node is unavoidable | Containment |
| --- | --- | --- |
| Playwright e2e and visual runner, per [ADR-0601](0601-testing-strategy.md) | browser-process control needs extra-fd pipe transport and worker IPC. Bun does not match these. The gap is upstream, not in our usage. The [support patch](https://github.com/microsoft/playwright/pull/28875) by Bun's own author and the [feature request](https://github.com/microsoft/playwright/issues/38095) are both unmerged | `test/e2e/.mise.toml`, runner and CI only |
| Lowdefy admin console, per [ADR-0401](0401-internal-admin.md) | installed and run, not built, so upstream chooses the runtime. Its CLI stops without `pnpm` on `PATH`. `lowdefy start` shells to `next start`, whose bin is `#!/usr/bin/env node`. Bun replaces Node there only by aliasing `node`, and still needs pnpm | `apps/admin/.mise.toml` and the image of that app |
| API mock, per [ADR-0600](0600-local-development-loop.md) | the only contract mock that is complete for OpenAPI 3.1 is a Node program | used as a pinned upstream container. It installs no Node anywhere and adds no `package.json` |

### What makes a language an escape hatch

An escape hatch adds a capability that Go lacks. A language that does what Go already does is a **substitute**. Adopting a substitute buys nothing and pays the full cost of driver 5. So JVM, .NET, and a JavaScript backend are barred, with or without an ADR. Each is stronger than Go on driver 3, and none adds a capability.

Rust and Python are complements, not substitutes. Each is admitted only on its condition in the decision table. Correctness preference is driver 3, and driver 3 alone does not outrank driver 5.

Every escape-hatch service has its own ADR that records the measured need. A Rust service also records how it meets [ADR-0500](0500-observability.md), given the maturity of its telemetry SDKs. A third escape hatch amends this ADR.

## Consequences

### Positive

- One language across the fleet. `libs/go/` is shared without conditions. There is one lint and format configuration, one base image, and one codegen pipeline. An engineer moves between services with no new toolchain.
- **The platform and the product are written in the same language.** A stack trace from a third-party component is readable. A fix to one is an ordinary pull request, not an upstream issue and a wait.
- **A service engineer and a platform engineer come from adjacent pools.** Cover during an absence does not need a second language. Growth from the first role into the second does not need one either.
- The own working set of a service dominates its resident memory, not its runtime. So fleet capacity tracks workload, per [ADR-0204](0204-resource-management.md).
- Generated TypeScript clients share types across languages without a second backend language, per [ADR-0303](0303-api-contracts-and-lifecycle.md).
- The decision comes from the axis position. A project that adopts this template at a different position knows which driver to re-run. It does not have to argue the language again.

### Negative and Risks

- **Go is not the strongest available language on driver 3.** This is accepted, on the ranking argued above.
- **Driver 1 has the weakest evidence here.** A labour market cannot be measured like a language feature. So the driver carries a re-derivation test, not a figure. A project in a different market re-runs the test before it inherits the answer.
- Verbose error handling is accepted. There are no custom error-handling DSLs.
- **The money type is first-party code on a correctness-critical path.** A bug in it is a bug in every price, total, and ledger entry at once. A language with a native decimal inherits a vetted implementation instead. The money type has no third-party dependency, so we test the exposure ourselves and do not trust others with it.
- **Bun is a single-vendor runtime with one implementation.** The exit is affordable only because its Node API compatibility is high enough to run the same code on Node. The islands already show that Node is installable.
- Every escape-hatch service is a permanent tax. It adds a toolchain, codegen pipeline, CI cache, base image, and review pool that exist for one service.

## Rules

- Every backend service is written in Go. Another language requires its own ADR that admits the service under a documented escape hatch.
- The root `.mise.toml` pins the Go version, and no service overrides it. Only a release that still receives upstream security fixes is pinned. Per the [Go release policy](https://go.dev/doc/devel/release), that is one of the two most recent major releases. `(CI: ci:lint)`
- A monetary amount is the shared money type, never a floating-point number. It is `numeric` in the database, a string in the OpenAPI schema, and a string on the wire. `(CI: lint:money)`
- The frontend is TypeScript.
- Bun is the only JS runtime for code we author. No Go service image, no frontend image, and no artifact built from our own source installs Node. `(CI: lint:node-scope)`
- Node is never pinned in the root `.mise.toml`. An island that installs Node pins it in its own island config, against the root `[env] NODE_VERSION`. An island that ships as a container pins no Node at all. A fourth Node island requires an amendment to this ADR. `(CI: lint:node-scope)`
- A Rust service requires its own ADR. It records the measured inadequacy of Go or a Rust-native canonical ecosystem, and how the service meets [ADR-0500](0500-observability.md).
- A Python service requires its own ADR, and is admitted only where the library ecosystem is the reason the service exists.
- JVM, .NET, and JavaScript backends are not permitted, with or without an ADR.
- Cross-language sharing uses generated OpenAPI clients, never a shared in-process runtime.
