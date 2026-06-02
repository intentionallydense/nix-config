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

  # Redistributable GPU/CPU firmware (linux-firmware). The slim install shipped without it,
  # which crippled BOTH GPUs: i915 couldn't load the KBL DMC blob so runtime power management
  # was DISABLED on the iGPU, and amdgpu couldn't load navi14_sos/smc so the dGPU never bound
  # and sat powered-but-unmanaged. This ships the DMC/GuC + Navi14 blobs so the iGPU
  # power-manages itself and amdgpu can bind + runtime-suspend the dGPU — the real battery/heat fix.
  hardware.enableRedistributableFirmware = true;

  # The AMD Navi14 dGPU can't suspend on T2: amdgpu's SMU suspend times out → failed GPU-reset storm
  # → frozen machine on resume (hard reboot). We never render on the dGPU under Linux (display is the
  # iGPU via the gmux, already routed to IGD), so keep amdgpu off it entirely. Fixes suspend, drops
  # the phantom eDP-2 amdgpu was advertising, and stops the reset hangs; iGPU firmware is unaffected.
  # Trade-off: external displays wired through the dGPU won't work — revisit with an unbind-before-
  # suspend hook if the dGPU is ever needed.
  boot.blacklistedKernelModules = [ "amdgpu" ];

  # T2 + iGPU: dodge the black-screen-on-resume bug.
  # mem_sleep_default=s2idle: T2 firmware has no working S3/deep; force modern standby or resume hangs.
  boot.kernelParams = [
    "i915.enable_guc=3"
    "mem_sleep_default=s2idle"
    "modprobe.blacklist=amdgpu" # belt-and-suspenders with boot.blacklistedKernelModules (above)
  ];

  # Initrd modules to find + mount the btrfs root on the internal NVMe at boot
  # (no hardware-configuration.nix here; apple-t2 layers apple-bce on top of these).
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];

  # Initial login password for chloride — CHANGE IT after first boot (`passwd`).
  # Without this the account is locked and SDDM won't let you in.
  users.users.chloride.initialPassword = "changeme";

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
