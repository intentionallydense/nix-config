# Fish shell — cross-platform.
# Base fish config shared between macOS and NixOS: greeting, common aliases,
# platform-aware rebuild command. macOS hosts extend this with additional
# interactiveShellInit (conda, ghcup, etc.) in home/default.nix.
# Used by: modules/home/default.nix
{ pkgs, lib, ... }:
{
  home-manager.sharedModules = [
    (_: {
      programs.fish = {
        enable = true;

        shellInit = ''
          set -g fish_greeting
        '';

        shellAliases = {
          ls = "eza";
          ll = "eza -la";
          la = "eza -a";
          tree = "eza --tree";
          cat = "bat";
          cls = "clear";
          nv = "nvim";
        } // lib.optionalAttrs pkgs.stdenv.isLinux {
          rebuild = "sudo nixos-rebuild switch --flake ~/NixOS# --show-trace";
        } // lib.optionalAttrs pkgs.stdenv.isDarwin {
          rebuild = "sudo darwin-rebuild switch --flake ~/projects/active/nix-config";
          publish = "python3 ~/projects/active/intentionallydense/publish.py --go --push";
          publish-dry = "python3 ~/projects/active/intentionallydense/publish.py";
        };
      };
    })
  ];
}
