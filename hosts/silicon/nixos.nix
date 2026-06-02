# NixOS configuration for "silicon" — 2019 16" MacBook Pro (MacBookPro16,1, Apple T2).
# Converted from macOS → NixOS. Reuses carbon's desktop modules (so it boots into the
# same Hyprland world); drops the entire server stack. All the T2-specific hardware
# (patched kernel, apple-bce, WiFi/BT firmware, iGPU/dGPU, audio) is handled by the
# nixos-hardware apple-t2 module — no hand-rolled firmware or gmux config needed.
{
  pkgs,
  inputs,
  videoDriver,
  hostname,
  browser,
  editor,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.apple-t2 # T2 kernel, apple-bce, WiFi/BT firmware, iGPU, audio
    inputs.disko.nixosModules.disko
    ./disko.nix

    ../../modules/hardware/video/${videoDriver}.nix
    ../common.nix
    ../../modules/scripts

    ../../modules/desktop/hyprland # same WM as carbon
    ../../modules/home # shared home-manager (starship, tmux, direnv, cli, git, fish, …)

    ../../modules/programs/browser/${browser}
    ../../modules/programs/editor/${editor}
    ../../modules/programs/shell/bash
    ../../modules/programs/misc/thunar
    ../../modules/programs/misc/nix-ld

    # Deliberately NOT imported (vs carbon):
    #   modules/server/*       — silicon's a laptop, not the server
    #   modules/server/power   — that's the always-on/never-suspend profile; a laptop wants the opposite
    #   modules/programs/secrets — needs the sops age key present; add after first boot
    #   modules/hardware/drives  — carbon-specific mounts
  ];

  # --- Apple T2: the whole 16" hardware story, declaratively ---
  hardware.apple-t2 = {
    enableIGPU = true; # boot the Intel iGPU and park the AMD dGPU (battery + stability)
    firmware = {
      enable = true; # provision BCM4364 WiFi/BT firmware (no manual Apple blobs)
      version = "sonoma"; # macOS version the firmware is sourced from; flip if WiFi is unhappy
    };
  };

  # T2 + iGPU: dodge the black-screen-on-resume bug.
  boot.kernelParams = [ "i915.enable_guc=3" ];

  networking.hostName = hostname;

  # Put silicon back on the tailnet (reachable as a peer, like before). `tailscale up` post-install.
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # SSH — tailnet + local only (mirrors carbon's posture; not exposed to WAN).
  services.openssh = {
    enable = true;
    openFirewall = false;
  };

  # T2 kernel binary cache — pull the patched kernel prebuilt instead of recompiling it
  # (the cache the t2linux project maintains). Merges with common.nix's substituter list.
  nix.settings = {
    substituters = [ "https://cache.soopy.moe" ];
    trusted-public-keys = [ "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo=" ];
  };
}
