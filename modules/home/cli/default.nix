# Common CLI tools — cross-platform.
# Configures bat, eza, fzf, htop, jq, ripgrep as home-manager programs
# (with shell integration) rather than bare packages.
# Used by: modules/home/default.nix
{ pkgs, ... }:
{
  home-manager.sharedModules = [
    (_: {
      home.packages = [ pkgs.tmuxp ];

      programs.bat.enable = true;

      programs.eza = {
        enable = true;
        enableFishIntegration = true;
        # Zsh integration disabled — modules/home/fish has custom eza aliases with --icons
      };

      programs.fzf = {
        enable = true;
        enableFishIntegration = true;
        enableZshIntegration = true;
      };

      programs.htop.enable = true;
      programs.jq.enable = true;
      programs.ripgrep.enable = true;
    })
  ];
}
