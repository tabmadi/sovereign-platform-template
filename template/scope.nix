# The template scope, per TPL-0000. The template module of tabnix adds the lint-scope check and the templates output.
{ inputs, ... }:
{
  imports = [ inputs.tabnix.flakeModules.template ];

  tabnix.template = {
    # The workflow of the template scope must stay in .github/workflows/ to run, so the copy leaves it out by name.
    exclude = [ ".github/workflows/template.yml" ];
    description = "A self-hosted platform monorepo, with every reusable decision recorded as an ADR and enforced in CI";
    welcomeText = ''
      # A new project

      1. In the new folder, run `git init` and `git add -A`. A flake sees only the files that git tracks.
      2. Run `nix develop`. It downloads the tools and installs the git hooks.
      3. Run `just init`. It asks seven questions, renames the project, and applies the setup modes.
      4. Run `just bootstrap`, then `just gen` and `just check`, and commit.
      5. Rewrite `README.md` for this project.
      6. Update the contacts in `.github/SECURITY.md` and the copyright line in `LICENSE`.
      7. Run Renovate from its workflow, per ADR-0117, and keep `.template-version` for the next update.
    '';
  };
}
