# SketchyBar — macOS menu bar replacement for AeroSpace workspace visualization.
# Catppuccin Mocha themed. Shows workspace indicators + clock.
# Used by: hosts/silicon/default.nix, hosts/germanium/configuration.nix
{ ... }:
{
  # SketchyBar is a formula (not cask) from a third-party tap
  homebrew.taps = [ "FelixKratz/formulae" ];
  homebrew.brews = [ "FelixKratz/formulae/sketchybar" ];

  home-manager.sharedModules = [
    ({ ... }: {
      xdg.configFile."sketchybar/sketchybarrc" = {
        source = ./sketchybarrc;
        executable = true;
      };
      xdg.configFile."sketchybar/plugins/aerospace.sh" = {
        source = ./plugins/aerospace.sh;
        executable = true;
      };
    })
  ];
}
