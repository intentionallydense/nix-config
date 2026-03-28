# Ghostty terminal emulator — cross-platform.
# Installed via homebrew cask on macOS, via nixpkgs on NixOS.
# Shared Catppuccin Mocha theme, no window decorations.
# Used by: modules/home/default.nix
{ pkgs, lib, ... }:
{
  home-manager.sharedModules = [
    (_: {
      # On Linux, install ghostty via nixpkgs. On macOS it's a homebrew cask.
      home.packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.ghostty ];

      xdg.configFile."ghostty/config".text = ''
        # Font
        font-family = JetBrainsMono Nerd Font
        font-size = 14

        # Theme
        theme = Catppuccin Mocha

        # Window
        window-decoration = false
        window-padding-x = 8
        window-padding-y = 4
      '' + lib.optionalString pkgs.stdenv.isDarwin ''

        # macOS
        macos-option-as-alt = true

        # Unbind cmd-shift-p so AeroSpace project picker takes priority
        keybind = super+shift+p=unbind
      '';
    })
  ];
}
