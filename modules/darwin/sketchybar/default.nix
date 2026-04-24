# SketchyBar — macOS menu bar replacement for AeroSpace workspace visualization.
# Catppuccin Mocha themed. Shows workspace indicators, front app, battery,
# volume, wifi, clock.
# Used by: hosts/silicon/default.nix, hosts/germanium/configuration.nix
#
# Plugins must be declared individually with executable = true;
# recursive = true on a directory doesn't preserve the execute bit.
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
      xdg.configFile."sketchybar/plugins/battery.sh" = {
        source = ./plugins/battery.sh;
        executable = true;
      };
      xdg.configFile."sketchybar/plugins/front_app.sh" = {
        source = ./plugins/front_app.sh;
        executable = true;
      };
      xdg.configFile."sketchybar/plugins/volume.sh" = {
        source = ./plugins/volume.sh;
        executable = true;
      };
      xdg.configFile."sketchybar/plugins/wifi.sh" = {
        source = ./plugins/wifi.sh;
        executable = true;
      };
    })
  ];
}
