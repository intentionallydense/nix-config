# Aerospace tiling window manager — darwin only.
# Deploys aerospace.toml to ~/.config/aerospace/ via home-manager.
# Used by: hosts/silicon/default.nix, hosts/germanium/configuration.nix
{ ... }:
{
  home-manager.sharedModules = [
    ({ lib, ... }: {
      home.activation.reloadAerospace = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        aerospace reload-config 2>/dev/null || true
      '';
      home.file.".config/aerospace/aerospace.toml".source = ./aerospace.toml;
      home.file.".config/aerospace/scripts/app-launcher.sh" = {
        source = ./scripts/app-launcher.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/keybinds.sh" = {
        source = ./scripts/keybinds.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/consolidate-workspaces.sh" = {
        source = ./scripts/consolidate-workspaces.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/swap-workspaces.sh" = {
        source = ./scripts/swap-workspaces.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/project-picker.sh" = {
        source = ./scripts/project-picker.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/session-switcher.sh" = {
        source = ./scripts/session-switcher.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/claude-session-picker.sh" = {
        source = ./scripts/claude-session-picker.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/scratchpad.sh" = {
        source = ./scripts/scratchpad.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/publish.sh" = {
        source = ./scripts/publish.sh;
        executable = true;
      };
    })
  ];
}
