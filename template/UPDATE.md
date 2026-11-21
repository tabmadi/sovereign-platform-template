# Updating a project to a newer template

A coding agent follows these steps to bring a project made from this template to a newer release, per [TPL-0000](adr/0000-template-contract.md). The project is the authority over its own files. The update brings the changes of the template and keeps every choice that the project made.

## Before you start

- Work in a clean checkout of the project, on a new branch.
- Read `.template-version` in the project. It holds the release that the project started from, or the release of its last update. Call it `OLD`.
- Choose the release to update to. Call it `NEW`. The releases are the tags of the template repository.
- Read the `AGENTS.md` of the project, and ADR-0001 for the house style.

## Steps

1. Clone the template next to the project, with its full history.

   ```bash
   git clone https://github.com/tabmadi/sovereign-platform-template.git template-src
   ```

2. List the files that changed between the two releases, outside `template/`.

   ```bash
   git -C template-src diff --stat OLD NEW -- . ':!template'
   ```

3. Read the project's names. `just init` replaced these values of the template:

   | Template value | Where the project's value is |
   | --- | --- |
   | `github.com/tabmadi/sovereign-platform-template` | The `module` line of `go.mod` |
   | `ghcr.io/tabmadi/sovereign-platform-template` | The image registry in `infra/gitops/` |
   | `example.com` | The apex host in `infra/gitops/` |
   | `example-<env>-<role>` | The node names in `infra/talos/inventory/` |

4. For each changed file, apply the change of the template to the file of the project.
   - Read the diff of the file: `git -C template-src diff OLD NEW -- <path>`.
   - Replace each template value of step 3 with the value of the project.
   - Where the project changed the same lines, keep the intent of the project and add the intent of the template. When the two conflict, stop and ask the owner.
   - A file that the project deleted stays deleted, unless the diff adds a feature that the project needs. Ask the owner when you cannot tell.
   - A new file of the template comes into the project with the names of the project.
   - Skip the files of a setup mode that the project did not choose: `infra/runner`, `infra/forge-host`, `infra/hypervisor`, and `infra/opentofu`. `docs/reference/modes.md` lists the modes.
   - A forgejo project keeps its workflows in `.forgejo/workflows/` with no `permissions` blocks. Apply a workflow change there. It also keeps `.forgejo/default_merge_message/SQUASH_TEMPLATE.md`, which the template has only after `just init`. Do not delete it.
   - The custom rules and generators are not files of the project. They arrive with the tabnix tag in `flake.nix`. Merge a change to `.config/tabrules.toml` like any other config.

5. Apply the changes of the lock files by running the tools, never by a text merge.
   - `flake.lock`: run `nix flake lock` after you change an input in `flake.nix`.
   - `go.sum`: run `go mod tidy`.
   - `bun.lock` and `bun.nix`: run `bun install`, then `just bun-nix`.

6. Write `NEW` into `.template-version`.

7. Run `just gen`, `just format`, and `just ci`. Fix each failure in the project, and repeat until `just ci` passes.

8. Commit with the title `chore: update to template NEW`, and open a pull request. Its description lists each conflict and how you resolved it.

## Rules

- An update never overwrites a change that the project made on purpose.
- The update is one pull request, and `just ci` passes on it.
- `.template-version` names the release that the project is on after the update.
