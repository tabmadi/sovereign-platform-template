# ADR-0107: Work Tracking

- **Status:** Accepted
- **Date:** 2026-11-03
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0001](0001-documentation-and-output-conventions.md), [ADR-0002](0002-tool-adoption.md), [ADR-0102](0102-source-control-and-ci.md), [ADR-0106](0106-dependency-updates.md), [ADR-0300](0300-data.md), [ADR-0306](0306-trust-tiers-and-urls.md), [ADR-0503](0503-error-tracking.md)
- **Decides:** The task manager of a project is the issues and projects of its own forge, in each forge mode, for technical and non-technical teams.

## Context

Every task is a forge issue. Three ADRs rest on that fact:

- [ADR-0001](0001-documentation-and-output-conventions.md) puts planned work there.
- [ADR-0503](0503-error-tracking.md) puts error triage there.
- [ADR-0102](0102-source-control-and-ci.md) counts issues in the review record that a forge move must carry.

The forge was compared as a forge, not as a task manager. Principle 7 of [ADR-0000](0000-platform-foundations.md) calls a tool with no recorded comparison an assumption. This ADR records the comparison.

Two groups use the tool, and they do different work:

| Group | Work | Touches a repository |
| --- | --- | --- |
| Engineers | open, link, and close work from commits and pull requests | yes |
| Teams that do not write code: product, design, support, sales, and operations | file requests, plan, and follow progress | no |

A project runs one of two forges, per the `forge` mode of [ADR-0106](0106-dependency-updates.md): `github` or `forgejo`. The answer can differ by mode, so this ADR decides for each mode.

**Sovereignty binds weakly here.** The task manager helps build the product and is not part of it. It is not on the product, deploy, or signing path. Development needs the internet in any case. So self-hosting is a differentiator in this ADR, not a gate. A managed tracker in the `forgejo` mode is still a dependency that principle 3 requires [ADR-0000](0000-platform-foundations.md) to record.

**A tracker is Tier 2**, per [ADR-0002](0002-tool-adoption.md). It holds tasks, comments, and links. Leaving it is an export and an import through two APIs. That takes weeks and touches no customer data.

Out of scope: incident records, per [the incident guide](../guide/incident-management.md), and what a service must do, per [ADR-0602](0602-behaviour-requirements.md). Support tickets from customers are a product concern.

## Decision drivers

The drivers come in two groups. An option that fails a gate is out. The options that pass every gate are compared on the differentiators, in rank order.

### Gates

1. **The product is viable for the life of the decision.** A vendor sells it, a maintainer fixes it, and no end date is announced. A tool that fails this loses every other strength with it.
2. **No new credential for each person.** Sign-in goes through an identity that the person already has: the forge, Kratos over OIDC, or a company mail domain. A separate password for each person is the cost this gate refuses.
3. **A person who does not use git can do the whole job.** They create a task, find it again, and follow it on a board or a list. No repository concept stands in the way.
4. **Every task leaves through an API.** Tasks, comments, and attachments export with no help from the vendor, per principle 4.

### Differentiators, in rank order

1. **Operating cost to this team**, per principle 2. A new component brings its runtime, its datastores, and its upgrades, and the floor is heavy already. A second database engine also contradicts [ADR-0300](0300-data.md).
2. **Price at the size of the team, with sign-in included.** A free tier often ends at a user or issue limit. Single sign-on is often in a higher plan.
3. **Access for agents and automation.** Coding agents in this repository read and update tasks. The platform also opens tasks itself: the quarterly upstream check and error triage both write issues.
4. **A merge closes its task.** A pull request that names a task closes it, with no step by hand and no bridge to maintain.
5. **Confidential work.** A security report is visible only to the people who handle it.
6. **Planning features beyond the gate.** Table views, timelines, custom fields, intake forms, and cycles.
7. **Self-hosted.** The tracker runs on infrastructure that we control.
8. **Configuration in the repository**, per principle 1. Forms, labels, and fields are committed files.

## Considered options

### Gates

| Option | 1: viable | 2: no new credential | 3: usable without git | 4: API export | Result |
| --- | --- | --- | --- | --- | --- |
| Forgejo issues and projects | yes | yes. The forge account, through Kratos, per [ADR-0306](0306-trust-tiers-and-urls.md) | yes. [Issue forms](https://forgejo.org/docs/latest/user/issue-pull-request-templates/), a filtered issue list across the organization, and [boards](https://forgejo.org/docs/latest/user/project/) | yes | passes |
| GitHub Issues and Projects | yes | yes. The GitHub account | yes. Forms, tables, boards, and roadmaps | yes | passes |
| Linear | yes | yes. Google sign-in on every plan, per its [pricing page](https://linear.app/pricing). SAML is in Enterprise | yes | yes | passes |
| Jira Cloud | yes | yes. Google and Microsoft sign-in. SAML needs the Atlassian Guard add-on | yes | yes | passes |
| Plane, cloud or Community Edition | yes | yes. Google and GitHub sign-in. SAML and OIDC are in paid plans, per its [pricing page](https://plane.so/pricing) | yes | yes | passes |
| OpenProject | yes | **only on a paid plan.** OIDC is in the Professional plan, per its [pricing page](https://www.openproject.org/pricing/) *(documented)* | yes | yes | passes with the Professional plan, so it is compared at that price |
| YouTrack, cloud or Server | yes | yes, through its OAuth 2.0 auth modules | yes | yes | passes |
| Vikunja | yes | yes, with Forgejo or Kratos as its OIDC provider | yes. List, board, Gantt, and table views | yes | passes |
| Asana, ClickUp, Notion, Trello, and Monday | yes | yes, through Google sign-in. SAML is in Business or Enterprise plans | yes | yes | passes. They share one row because no differentiator separates them from Linear |
| Huly, Leantime, Tuleap, and WeKan | yes | yes | yes | yes | passes, and each loses on the first differentiator below |
| Jira Data Center, self-hosted | **no.** New sales ended on 2026-03-30. Every Data Center product turns read-only after 2029-03-28, per [Atlassian](https://www.atlassian.com/licensing/data-center-end-of-life) *(documented)* | | | | out |
| Taiga | **no.** Its makers left it, and its successor Tenzu had its first stable release in September 2025, per [the Taiga forum](https://community.taiga.io/t/launching-tenzu-taiganext-new-identity/3940) *(documented)* | | | | out |
| Focalboard | **no.** It has no maintainer, per [its repository](https://github.com/mattermost-community/focalboard/issues/5038) *(documented)* | | | | out |
| Redmine | yes | only through a third-party plugin | **no.** The interface and the board plugins assume a technical user *(reasoned)* | yes | out |
| Planka and Kanboard | yes | varies | **no.** Boards only, with no list across projects *(reasoned)* | yes | out |
| GitLab CE issues | yes | yes | yes | yes | out on a decision, not a gate. It is a second forge, which [ADR-0102](0102-source-control-and-ci.md) rejects on principle 2 |
| GitHub Enterprise Server | yes | **no.** Built-in accounts, CAS, LDAP, and SAML only, per [its docs](https://docs.github.com/en/enterprise-server@3.18/admin/concepts/identity-and-access-management/identity-and-access-management-fundamentals) *(documented)* | yes | yes | out. It is also a second forge |

### Differentiators

The table holds the options that passed. A cell shows the facts, and the verdict names the rank that decided the row.

| Option | 1: operating cost | 2: price | 3: agents and automation | 4: a merge closes its task | 5: confidential work | 6: planning features | 7: self-hosted | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Forgejo issues and projects** | none. It is Core already | free, with no limit | a full REST API. MCP servers come from the community | yes, in the `forgejo` mode | a private repository | forms, scoped labels, milestones, dependencies, and boards. No table, timeline, or custom field | yes | **Chosen for the `forgejo` mode.** It ties for first on ranks 1 and 2 and leads on rank 4 *(reasoned)*. Rank 6 is its weak point, and the deferral below watches it |
| **GitHub Issues and Projects** | none | free, with no limit | REST, GraphQL, and an official MCP server | yes in the `github` mode. **No** in the `forgejo` mode, where the issues live apart from the code | a private repository and private security advisories | tables, boards, roadmaps, custom fields, and iterations | no | **Chosen for the `github` mode**, where it leads or ties on every rank but 7 *(reasoned)*. In the `forgejo` mode it is the runner-up: the gap on rank 3 is who maintains the MCP server, and the gap on rank 4 is whether a merge closes the task *(reasoned)* |
| Linear | none | free up to 250 issues and two teams, then a per-user plan, per its [pricing page](https://linear.app/pricing) *(documented)* | an API, webhooks, and an official MCP server on every plan | no. Its integrations name GitHub and GitLab, not Forgejo | private teams | the deepest in the table: cycles, projects, roadmaps, and triage | no | Loses on rank 2. The free tier ends at 250 issues, so a working team pays for each user *(documented)*. It leads on rank 6, so it is the first managed option that the trigger reopens |
| Jira Cloud | none | free up to 10 users. Single sign-on needs Atlassian Guard on top | a REST API | no. Its integrations name GitHub, GitLab, and Bitbucket | issue security levels | timelines, custom fields, and configurable workflows | no | Loses on rank 2 for the same reason as Linear, and its workflows need an administrator to keep them *(reasoned)* |
| Plane cloud | none | free up to 12 users, then a per-user plan | an API and an official MCP server | no. Its GitHub and GitLab integrations are paid | private projects | cycles, modules, pages, and views | no | Loses on rank 2 at more than 12 users *(documented)*. Below that size it is the closest managed rival to Linear |
| Plane Community Edition | several app services, Postgres, Redis, RabbitMQ, and an S3 store | free | an API and an official MCP server | no | private projects | the same as Plane cloud | yes | Loses on rank 1. It is the heaviest stack that passed the gates, after Huly *(reasoned)* |
| OpenProject Professional | one Rails app, a Postgres tenant on CNPG, and a cache | a per-user plan, because the free edition fails gate 2 | an API. Its MCP server is a paid add-on | no. It integrates with GitHub and GitLab | project permissions | Gantt, boards, a wiki, time tracking, and custom fields | yes | Loses on ranks 1 and 2 *(documented)*. It is the strongest self-hosted option, so it is the choice for a project where sovereignty binds for the tracker |
| YouTrack | none on cloud. One JVM app with an embedded database when self-hosted, so its backups are outside CNPG | free up to 10 users, then user packs, per [JetBrains](https://sales.jetbrains.com/hc/en-gb/articles/28382529526162-Changes-to-YouTrack-Server-subscriptions-prices) *(documented)* | an API and a built-in MCP server | not confirmed for Forgejo | issue visibility groups | boards, Gantt, a helpdesk, and a knowledge base | either | Loses on rank 2 above 10 users, and on rank 1 when self-hosted |
| Vikunja | one Go binary and a Postgres tenant | free | a REST API | no | shared projects with permissions | list, board, Gantt, and table views. No intake form | yes | Loses on rank 1 against Forgejo, which costs nothing new, and on rank 6 against the managed options *(reasoned)* |
| Asana, ClickUp, Notion, Trello, and Monday | none | free tiers end at a user or feature limit. Single sign-on is in Business or Enterprise plans | APIs | no | varies | strong | no | Each matches Linear on ranks 1 to 5 and does not pass it on rank 6 *(reasoned)* |
| Huly, Leantime, Tuleap, and WeKan | Huly needs CockroachDB, Elasticsearch, and Redpanda, per [huly-selfhost](https://github.com/hcengineering/huly-selfhost). Leantime and Tuleap need MySQL, per [Tuleap's requirements](https://docs.tuleap.com/installation-guide/step-by-step/requirements.html). WeKan needs MongoDB *(documented)* | free | APIs | no | varies | varies | yes | Each loses on rank 1. A second database engine is the cost that [ADR-0300](0300-data.md) rejects |
| A view layer over the forge's issues | one stateless app | free, plus the work to build it | the forge's API | yes | the forge's | the views that the app builds: tables, boards by any label scope, and timelines | yes | Not the default, because a project builds and keeps it. It is the first answer to the trigger when the gap is views, not data *(reasoned)* |
| Two tools: the forge for engineers, a second tracker for the other teams | the second tool | the second tool | the second tool | **no.** Work that crosses teams lives in two places, or a sync keeps two copies | varies | the second tool's | varies | Loses on rank 4 for every task that crosses teams, and adds a sync mechanism to rank 1 *(reasoned)* |
| The forge's issues with no conventions, the do-nothing baseline | none | free | the forge's API | yes | no rule for it | no forms, no team boards, and no home for work with no code | the forge's answer | The tool of the chosen rows without their Decision. The other teams keep work in chat and documents, so a second backlog grows anyway |

**Ranks 1 and 2 decide the table.** The forge's own issues cost nothing to run and nothing to buy, at any team size. Every managed tracker also costs nothing to run, so price separates them. A team that ranks planning features above price picks Linear, or Plane below 12 users.

## Decision

The task manager of a project is the issues and projects of its own forge. We do not run a second tracker.

| Forge mode | Task manager | Sign-in |
| --- | --- | --- |
| `github` | GitHub Issues and Projects | the GitHub account |
| `forgejo` | Forgejo issues and projects | the forge account, through Hydra and Kratos over OIDC, per [ADR-0306](0306-trust-tiers-and-urls.md) |

### Conventions in both modes

| Concern | Decision |
| --- | --- |
| Where a task lives | an issue in the repository where its change lands. Work with no code change lives in a repository named `work`, which holds no code |
| How a request enters | an issue form, with labels that the form sets |
| How work is classified | scoped labels: `kind/`, `team/`, and `priority/` |
| What is committed | the issue forms and the label set, per principle 1 of [ADR-0000](0000-platform-foundations.md) |
| How work is planned | one organization project for each team. An issue from any repository of the organization can sit on it |
| Dates and order | milestones for a release or a date, a due date on an issue, and issue dependencies for order |
| How work is done | a pull request closes the issue that it resolves with a closing keyword. A task with no code change is closed by hand |
| Confidential work | a security report lives in a private repository that only its handlers can read |
| What a team that does not write code reaches | in the `forgejo` mode, issues and projects only, through the unit permissions of its forge team. GitHub has no role with issues and no code, so the `github` mode grants the lowest role that can triage |

### Where a tracker sits on the adoption path

| Tracker | Place | Why |
| --- | --- | --- |
| The forge's issues | moves with the forge, Band 2 rank 7 of [`adoption-path.md`](../adoption-path.md) | it is the forge, so it adds no row |
| A managed tracker in the `forgejo` mode | a recorded dependency in principle 3 of [ADR-0000](0000-platform-foundations.md) | it is a component that we do not run |
| A self-hosted tracker beside the forge | Opt-in, per [`operational-surface.md`](../operational-surface.md) | the forge covers the concern in part, so it cannot join Core |

### A view layer is the first answer to a gap in views

The forge holds the data that a planning view needs: labels, milestones, due dates, dependencies, and tracked time. A small app over the forge's API can show that data as a table, a board by any label scope, or a timeline. The tasks stay in the forge, so ranks 2 to 5 still hold. Leaving the app deletes code, not data.

### The forge's planning features are watched

| Field | Value |
| --- | --- |
| **Trigger** | three issues with the `kind/tracker-gap` label in one quarter. Each one records a planning need that the forge cannot hold, such as a timeline across tasks, a custom field, or a table view |
| **What fires** | a view layer over the forge's API is weighed first, when the gap is views and not data. Otherwise the differentiator table is read again at the team size of that day. Linear, Plane, and GitHub Projects are its first rows. OpenProject replaces them when sovereignty binds for the tracker |
| **Seam** | ✗ none. No importer reads Forgejo, so a move is a script between two APIs. This is a **bet** |
| **Cost if adopted late** | the issue body to migrate grows for as long as the decision waits. Commit and pull request links stay in the forge and do not migrate. A managed tracker also loses rank 4: a merge no longer closes its task |

## Consequences

### Positive

- No component joins the floor, and no tracker bill starts.
- No person gets a new credential. Offboarding the forge account ends access to the tracker.
- A pull request closes its task. No sync mechanism exists to fail.
- Agents and platform automation use one API for code, review, and tasks.
- Request forms and labels are reviewed in pull requests like any other configuration.

### Negative and Risks

- **People who do not write code work in a developer tool.** The `work` repository, the forms, and the team boards hide most repository concepts. This cost is accepted for ranks 1 and 2.
- **The `forgejo` mode has no table, timeline, or custom field.** Milestones and scoped labels cover dates and classes. The `kind/tracker-gap` label measures the remaining gap, and it is the trigger.
- **The two modes differ in planning features.** A project that moves from `github` to `forgejo` loses tables, roadmaps, and custom fields. Its migration also carries every issue, as [ADR-0102](0102-source-control-and-ci.md) already states.
- **A forge outage stops planning as well as delivery and review.** Running workloads are not touched, per [`operational-surface.md`](../operational-surface.md).
- **In the `github` mode, a person who does not write code can read the code.** GitHub has no role with issues and no code. Repository visibility is the only control.
- **A move to another tracker is a bet.** A late move costs a migration script, and old commit links stay in the forge.

## Rules

- The task manager of a project is the issues and projects of its forge, per the `forge` mode of [ADR-0106](0106-dependency-updates.md). No second tracker holds the state of a task, per principle 5 of [ADR-0000](0000-platform-foundations.md).
- A tracker gives no person a new credential. Sign-in goes through an identity that the person already has.
- Work with no code change lives in a repository named `work`, which holds no code.
- A request enters through an issue form. The forms and the label set are committed files, per principle 1 of [ADR-0000](0000-platform-foundations.md).
- Each team plans on one organization project.
- A pull request closes the issue that it resolves with a closing keyword.
- A security report lives in a private repository that only its handlers can read.
- In the `forgejo` mode, a forge team whose members do not write code has the issues and projects units only, never the code unit.
- A planning need that the forge cannot hold is filed as an issue with the `kind/tracker-gap` label. Three such issues in one quarter reopen this comparison.
- A managed tracker in the `forgejo` mode is recorded in principle 3 of [ADR-0000](0000-platform-foundations.md) before it is adopted.
