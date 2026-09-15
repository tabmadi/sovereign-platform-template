## Unreleased (ed7b4e5..ae46d1e)
#### Features
- (**template**) add project:init and the project-identity gate - (8d6184f) - Tab
- package the repo as a Copier template with per-environment gitops - (c188403) - Tab
- move the local tier to kind, and add mail, alerting, storage, registry and analytics - (e57179c) - Tab
- add the CI gates, supply-chain signing and workload hardening - (9af072b) - Tab
- add the observability stack - (19e59e3) - Tab
- add the platform services, APIs, authz and admin console - (c02be24) - Tab
- add the monorepo toolchain, local k3d cluster and ArgoCD gitops - (e31ec90) - Tab
- prototype the Go service layout behind a Tyk gateway - (ed7b4e5) - Tab
#### Bug Fixes
- (**ci**) save a partial registry mirror, and name the docker hub identity - (499503d) - Tab
- (**ci**) skip the image matrix when no service is affected - (032b4ca) - Tab
- (**cluster**) create the mirror path before docker does, and wait for it to serve - (b5d7ccf) - Tab
- (**cluster**) report the registry log of the images that missed, not the tail - (7b089d7) - Tab
- (**cluster**) print the registry log when the warm misses - (071eb6f) - Tab
- (**cluster**) retry a missed registry warm, and report the status that missed - (a58b378) - Tab
- (**deps**) take bun 1.4.2, which survives the Next 16.3 build on musl - (ada09fd) - Tab
- (**deps**) take the next and grpc releases that fix CVE-2026-75604 and CVE-2026-84445 - (e89eee2) - Tab
- (**deps**) take the grpc release that fixes CVE-2026-84304 - (791aaee) - Tab
- (**registry**) authenticate the docker hub sync so a shared runner ip is not the limit - (78f9d98) - Tab
- (**release**) name the template stamp in the dry-run cleanup hint - (3ad2ec6) - Tab
- (**secrets**) repoint the tyk fingerprint at the squashed root commit - (b6f5716) - Tab
- (**supply-chain**) skip the image inventory in the template, which signs nothing - (ae46d1e) - Tab
- (**toolchain**) improve token handling and add pip configuration for retries - (d693be9) - Tab
#### Performance
- (**ci**) restore the registry mirror in the e2e and perf suites - (4dd5afe) - Tab
- (**ci**) carry the registry mirror between runs - (2a155b6) - Tab
- (**cluster**) warm only the images the tier will run - (67b5f4c) - Tab
#### Tests
- (**template**) add the generation fixture matrix - (82149ec) - Tab
#### Refactor
- (**cluster**) keep the mirror on one path for every environment - (3b58108) - Tab
- reset the architecture and record the foundational ADRs - (165857d) - Tab


