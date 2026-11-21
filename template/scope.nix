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

      Follow `Starting a project` in `README.md`.
    '';
  };
}
