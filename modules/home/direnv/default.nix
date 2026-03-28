# Direnv + nix-direnv — cross-platform.
# Used by: modules/home/default.nix
{ ... }:
{
  home-manager.sharedModules = [
    (_: {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
        enableFishIntegration = true;
        enableNushellIntegration = true;
        # Silence the verbose direnv output
        config.global.hide_env_diff = true;
      };
    })
  ];
}
