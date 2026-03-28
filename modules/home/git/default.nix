# Git + Delta — cross-platform.
# Manages: git identity, SSH signing, delta pager with side-by-side diffs.
# Used by: modules/home/default.nix
{ ... }:
{
  home-manager.sharedModules = [
    (_: {
      programs.git = {
        enable = true;

        signing = {
          key = "~/.ssh/id_ed25519.pub";
          signByDefault = true;
          format = "ssh";
        };

        settings = {
          user = {
            name = "saliva";
            email = "sylvestria.h@gmail.com";
          };
          init.defaultBranch = "main";
          merge.conflictstyle = "zdiff3";
          diff.colorMoved = "default";
        };
      };

      # Delta — side-by-side git pager with syntax highlighting.
      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options = {
          navigate = true;
          dark = true;
          side-by-side = true;
        };
      };
    })
  ];
}
