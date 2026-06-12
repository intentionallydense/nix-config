# tin — Hetzner Cloud VPS (x86_64), Sylvia's home-server-in-the-cloud.
#
# Phase 1 scope: the serving stack only (media / music / books / invidious /
# monitoring). The briefing-coupled automation (briefing, AOTD,
# overnight-research, publish-blog) stays on carbon for now — it's tied to the
# Obsidian vault + claude auth, a deliberate Phase-2 follow-up.
#
# Deliberately does NOT import hosts/common.nix: that carries the full Hyprland
# desktop (sddm, pipewire, bluetooth, printing, X). This box is headless, so it
# defines its own lean base below.
{
  pkgs,
  lib,
  config,
  username,
  hostname,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    # --- serving stack (Phase 1) ---
    ../../modules/server/media # Jellyfin + Immich (Sonarr/Radarr/Prowlarr disabled in-module)
    ../../modules/server/music # Navidrome, slskd, music-shelf, auto-import (AOTD masked below)
    ../../modules/server/books # Calibre-Web (kobo-briefing masked below; kobo-sync is udev-only)
    ../../modules/server/invidious # Invidious + podman companion (port 3001). PR-5736
    #   patch vendored 2026-06-12 (was a live draft-PR fetchpatch that drifted).
    #   ⚠ DC-IP result (tested 2026-06-12): potoken GENERATES but fails validation —
    #   googlevideo returns non-200 for every stream format from the Hetzner IP, so
    #   playback is dead from here. Service + migrated DB left in place. Fix path:
    #   set companion's networking.proxy to a wireproxy/Mullvad SOCKS endpoint when
    #   Sylvia's WG key lands (same key as the slskd plan). Until then Yattee stays
    #   pointed at carbon's instance.
    ../../modules/server/mullvad-egress # wireproxy → ch-zrh-wg-005: slskd SOCKS5 + companion HTTP
    ../../modules/server/monitoring # Prometheus + Grafana
    ../../modules/server/alerts # ntfy health alerts

    # NOT imported: power (laptop lid/charge), sunshine (GPU desktop streaming),
    # backup (external SanDisk — retarget to a Storage Box in a follow-up),
    # briefing (Phase 2), the desktop modules, and common.nix (desktop base).
  ];

  networking.hostName = hostname;

  # ===========================================================================
  # Lean headless base — the essentials common.nix provides, minus the desktop.
  # ===========================================================================
  users.users.${username} = {
    isNormalUser = true;
    # Libraries live in /srv/media (see flake.nix tinSettings), so no service
    # ever needs to traverse $HOME — no ACL hack, plain private home. (carbon
    # still uses the 0710 + named-user-ACL scheme; see modules/server/music.)
    homeMode = "0700";
    extraGroups = [ "wheel" ]; # "media" is added by modules/server/media
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcyLHliraFUz41modhQ3h60SH+6xZio0x7aJvqas94M fluoride@carbon"
    ];
  };
  users.users.root.openssh.authorizedKeys.keys = [
    # carbon's key, for the nixos-anywhere install + first-boot recovery.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcyLHliraFUz41modhQ3h60SH+6xZio0x7aJvqas94M fluoride@carbon"
  ];

  # Migration shim: the music tooling (music-import + siblings, beets config)
  # predates the /srv/media move and resolves the library via $HOME — on carbon
  # AND in the library's own scripts/ dir, which final-cutover rsync will keep
  # overwriting. One symlink keeps it all working verbatim until the Phase-2
  # script redo makes paths explicit — delete this then.
  systemd.tmpfiles.rules = [
    "L+ /home/${username}/music_library - - - - /srv/media/music"
  ];

  programs.fish.enable = true;
  # iodide's login shell is fish (set in the user block above). root deliberately
  # stays on bash so remote `nixos-rebuild`/tooling over SSH isn't parsed by fish.
  security.polkit.enable = true;
  nixpkgs.config.allowUnfree = true;

  # Locale / time — match carbon.
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        username
      ];
    };
    # Store hygiene — carbon gets this from common.nix (nh clean + optimise);
    # tin doesn't import common.nix, so set the equivalent directly. A headless
    # box that's only ever rebuilt remotely wants the plain nix.gc timer, not
    # nh's interactive rebuild wrapper. Keeps a 2-week rollback runway.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    optimise.automatic = true;
    # Pure-flake box: drop the vestigial nixos-unstable channel the
    # nixos-anywhere installer left in root's profile (and its NIX_PATH).
    channel.enable = false;
  };

  # ===========================================================================
  # Networking — DHCP on the Hetzner NIC; tailnet-gated firewall (carbon's model).
  # ===========================================================================
  networking.useDHCP = lib.mkDefault true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
    openFirewall = false; # not opened on the public NIC by the module itself
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraSetFlags = [ "--ssh" ];
  };
  # carbon's posture: services bind 0.0.0.0 but only tailscale0 is trusted, so
  # everything is tailnet-only. The firewall is the gate, not the bind address.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  # No allowedTCPPorts: tin is on the tailnet now, so SSH (and everything else)
  # is reachable only over tailscale0 — the public NIC exposes nothing but ICMP.
  # (Bootstrap briefly opened 22 here for the nixos-anywhere install; removed
  # 2026-06-12 once `tailscale status` showed tin connected.)

  # ===========================================================================
  # Boot loader — Hetzner Cloud is UEFI; systemd-boot. ESP comes from disko.
  # ===========================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Fallback if the cloud box won't let us write EFI vars at install:
  #   boot.loader.efi.canTouchEfiVariables = false;
  #   boot.loader.systemd-boot.efiInstallAsRemovable = true;

  # ===========================================================================
  # Secrets — sops-nix, decrypted with tin's OWN host SSH key (the server
  # pattern; carbon/silicon/germanium use user keys). After first boot, derive
  # the age recipient from /etc/ssh/ssh_host_ed25519_key.pub via ssh-to-age, add
  # it to .sops.yaml, and `sops updatekeys`. These declarations mirror carbon's
  # host config — the modules reference these secrets but don't declare them.
  # ===========================================================================
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.grafana_secret_key = {
      owner = "grafana";
    };
    secrets.navidrome_user = { };
    secrets.navidrome_pass = { };
    secrets.slskd_api_key = { };
    secrets.slskd_slsk_username = { };
    secrets.slskd_slsk_password = { };
    secrets.slskd_web_username = { };
    secrets.slskd_web_password = { };
  };

  # ===========================================================================
  # Mask the hardware/location-bound + Phase-2 units that ride in via the
  # music/books modules. enable=false masks the unit, so the timers never fire.
  # ===========================================================================
  # Bedroom Bluetooth speaker — physically in Sylvia's room, unreachable here.
  systemd.services.aotd-play.enable = lib.mkForce false;
  systemd.timers.aotd-play.enable = lib.mkForce false;
  systemd.services.aotd-play-failure.enable = lib.mkForce false;
  # AOTD download is briefing-coupled (Phase 2, stays on carbon for now).
  systemd.services.aotd-download.enable = lib.mkForce false;
  systemd.timers.aotd-download.enable = lib.mkForce false;
  # Kobo briefing-kepub builder is briefing-coupled (Phase 2). Calibre-Web's
  # library + OPDS feed stay live; only the daily kepub job is masked.
  systemd.services.kobo-briefing.enable = lib.mkForce false;
  systemd.timers.kobo-briefing.enable = lib.mkForce false;
  systemd.services.kobo-briefing-failure.enable = lib.mkForce false;
  # mp3-sync (Fiio DAP) and kobo-sync (Kobo USB) are udev-triggered only — the
  # devices never appear on a cloud box, so they self-gate. Left as-is.

  # Held back at Sylvia's request: the vault/claude-coupled automation gets a
  # clean redo later, not a straight port. (music-auto-import was unmasked
  # 2026-06-12 when tin took over the Soulseek login — it's pure library
  # plumbing, no vault coupling; see the $HOME migration shim above.)
  systemd.services.carbon-alert-check.enable = lib.mkForce false; # health-check ntfy pings
  systemd.timers.carbon-alert-check.enable = lib.mkForce false;

  system.stateVersion = "25.05";
}
