# TPL-0000: Template contract

- **Status:** Accepted
- **Decides:** Which files are the template and which are the project, how a project is made and updated, and what this template may hold.

## Context

This repo is a template for a self-hosted platform monorepo. A project made from it copies its files, and the copies do not link back. So every sentence in a copied file must stay true in the project. A sentence that names the template or another repo turns false in the copy.

This repo starts from [github-project-template](https://github.com/tabmadi/github-project-template) and adds the platform and its full ADR set. The [blueprints](https://github.com/tabmadi/blueprints) repo keeps the templates of the same size in step.

A project also changes after the copy. The template keeps changing too, so a project needs a way to take a later version.

## Decision drivers

1. **True in the copy.** No copied file names the template.
2. **One way to make a project.** Both ways to copy end in the same files.
3. **A cheap update.** A project takes a later version with no tool that the toolchain of ADR-0100 does not already hold.
4. **The project decides.** An update never overwrites a change that the project made on purpose.

## Considered options

### Making a project

| Option | 1 True in the copy | 2 One way | 3 Cheap | Verdict |
| --- | --- | --- | --- | --- |
| Copier, with a `copier.yml` of questions | Yes, through its exclusions | Two ways that a test keeps equal | Needs Python and a pinned Copier | Rejected on driver 3. ADR-0100 allows one tool manager, and Copier is a second one |
| Cookiecutter | Yes | No update at all | Needs Python | Rejected on drivers 3 and 4 |
| **`nix flake new -t`, then `just init`** | **Yes. The template module of tabnix leaves `template/` out** | **Yes. `just init` removes `template/` in a clone too, and `test-template` compares the two** | **Yes. Nix and `just` are already there** | **Chosen** |

Sources:

- `nix flake new -t` copies the `path` of a template output: [Nix manual, nix flake new](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake-new).
- Copier updates by a 3-way merge of two renders: [Copier docs, updating a project](https://copier.readthedocs.io/en/stable/updating/).
- Cookiecutter has no update: [Cookiecutter docs](https://cookiecutter.readthedocs.io/).

### Updating a project

| Option | 3 Cheap | 4 The project decides | Verdict |
| --- | --- | --- | --- |
| `copier update` | Needs Python and Copier | Yes, a conflict for each change of the project | Rejected on driver 3 |
| A git remote of the template, merged now and then | Yes | Yes | Rejected. It pulls the whole history of the template, with every file that `just init` removed |
| **A coding agent applies the diff between two versions, then `just ci` decides** | **Yes. `git diff` and the gate** | **Yes. The agent reads each change and keeps the choices of the project** | **Chosen** |

Sources:

- `git diff` between two tags of the template gives the change: [git-diff](https://git-scm.com/docs/git-diff).

## Decision

### Two scopes

| Scope | Holds | In a project |
| --- | --- | --- |
| Project | Every file outside `template/`, written in the voice of the project | Copied |
| Template | The `template/` folder: this ADR, the agent hints, the update guide, the fixtures, and the template checks | Not copied |

`flake.nix` loads `template/scope.nix` when it exists. That file imports the template module of tabnix and sets its description and welcome text. The module adds the `lint-scope` check and the `templates` output. A project has no `template/` folder, so it adds nothing.

### Making a project

`nix flake new -t github:tabmadi/sovereign-platform-template <dir>` copies the project scope, and the welcome text lists the first steps. GitHub's template button copies every file, `template/` included.

In both copies, `just init` asks seven questions: the product name, the slug, the Go module path, the apex host, the image registry, the forge, and the provisioning. It runs `scripts/project-rename.sh` and `scripts/forge-mode.sh`, removes the files of the modes that the project did not choose, and removes `template/`. Then it removes itself. `just test-template` makes a project from each fixture in `template/test/fixtures/` both ways, and fails when the two differ.

### Updating a project

`.template-version` holds the release or commit of the template that the project started from. A release of the template writes the release into the tree. `master` can be ahead of that release, so each way of making a project records the exact commit. The welcome text of `nix flake new` prints the command with the commit of the copy. The steps for the template button find the commit from the date of the first commit.

A coding agent updates a project with [UPDATE.md](../UPDATE.md). It diffs the template from that version to the new one. It applies each change with the names of the project and keeps every choice that the project made. It writes the new version into `.template-version`, and the update passes `just ci`.

### What this template holds

The sample services show the structure, not a feature set. A project builds its own services from `services/_template/` and removes the samples it does not need.

A dependency added here is a dependency of every project. So the template adds one only when the template itself needs it.

## Consequences

The root `README.md` describes the template. A new project rewrites it, and the welcome text says so.

`.github/workflows/template.yml` must stay in `.github/workflows/` to run. `scope.nix` leaves it out of the `templates` output, and `just init` removes it from a clone. A check on the repository name stops it in any other copy.

An update is only as good as the agent and the gate. The gate catches what breaks, and the review of the pull request catches what the gate cannot see.

## Rules

- Every file that a project must not inherit lives in `template/`, except the workflow of the template, which `scope.nix` leaves out by name.
- A file outside `template/` never links into it. `(CI: lint-scope)`
- A project doc never names another repo or speaks as the template. `(CI: lint-scope)`
- Both ways to make a project end in the same files. `(CI: test-template)`
- The template adds a dependency only when the template itself needs it.
- A change to a shared project ADR starts in github-project-template and goes to every template of the same size in one pass. This template is of the platform size.
