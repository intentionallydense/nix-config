{
  pkgs,
  config,
  videoDriver,
  username,
  hostname,
  browser,
  editor,
  terminal,
  terminalFileManager,
  vaultName,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/hardware/video/${videoDriver}.nix # Enable gpu drivers defined in flake.nix
    ../../modules/hardware/drives

    ../common.nix
    ../../modules/scripts

    ../../modules/desktop/hyprland # Enable hyprland window manager
    # ../../modules/desktop/i3-gaps # Enable i3 window manager

    ../../modules/home # Shared home-manager modules (starship, tmux, direnv, etc.)

    # ../../modules/programs/games
    ../../modules/programs/browser/${browser} # Set browser defined in flake.nix
    ../../modules/programs/editor/${editor} # Set editor defined in flake.nix
    ../../modules/programs/shell/bash # NixOS system-level bash config
    # ../../modules/programs/media/discord
    # ../../modules/programs/media/spicetify
    # ../../modules/programs/media/youtube-music
    # ../../modules/programs/media/thunderbird
    # ../../modules/programs/media/obs-studio
    # ../../modules/programs/media/mpv
    ../../modules/server/power       # Always-on laptop: lid ignore, no suspend, 80% charge cap
    ../../modules/server/media       # Jellyfin, Sonarr, Radarr, Prowlarr
    ../../modules/server/music       # Navidrome, slskd, beets, music-shelf, auto-import, AOTD
    ../../modules/server/monitoring  # Prometheus + Grafana
    ../../modules/server/owntracks   # Location tracking (OwnTracks Recorder)
    ../../modules/server/samba       # Network file shares (music, projects)
    ../../modules/server/backup      # Weekly + monthly rsync backups to external SanDisk 2TB
    ../../modules/server/sunshine    # Remote desktop streaming (Moonlight client)
    ../../modules/programs/misc/thunar
    ../../modules/programs/misc/lact # GPU fan, clock and power configuration
    ../../modules/programs/misc/nix-ld
    # ../../modules/programs/misc/virt-manager
  ];

  # Home-manager config
  home-manager.sharedModules = [
    (_: {
      home.packages = with pkgs; [
        # obsidian
        # github-desktop
      ];
    })
  ];

  # Define system packages here
  environment.systemPackages = with pkgs; [
    mosh
    vim
    wget
    waybar
    wofi
    wl-clipboard
    grim slurp
    swaynotificationcenter
    git
    signal-desktop
    jetbrains.rust-rover
    spotify
    jetbrains.pycharm-oss
    mullvad-vpn
    zotero
    # obsidian
    taskwarrior3
    # gcalcli
    python3
    curl
    git
    spawn_fcgi
    sops           # secrets editing (sops-nix)
    ssh-to-age     # derive age keys from SSH keys

    # familiar sensors
    ffmpeg        # webcam capture
    sox           # audio (play notification sounds)
    libnotify     # desktop notifications

    # Publishing pipeline — image resizing for publish.py
    imagemagick
    obsidian
  ];

  # --- sops-nix — system-level secrets decrypted at activation ---
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/home/${username}/.ssh/id_ed25519" ];
    secrets.grafana_secret_key = { owner = "grafana"; };
    secrets.navidrome_user = { };
    secrets.navidrome_pass = { };
    secrets.slskd_api_key = { };
    secrets.slskd_slsk_username = { };
    secrets.slskd_slsk_password = { };
    secrets.slskd_web_username = { };
    secrets.slskd_web_password = { };
  };

  networking.hostName = hostname; # Set hostname defined in flake.nix

  # Stream my media to my devices via the network
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "${username}";
    dataDir = "/home/${username}"; # default location for new folders
    configDir = "/home/${username}/.config/syncthing";
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.firewall.allowedUDPPortRanges = [ { from = 60000; to = 61000; } ]; # mosh

  # LLM Interface web UI — starts on boot, reachable over Tailscale
  systemd.services.claude-wrapper = let
    python = pkgs.python313.withPackages (ps: with ps; [
      anthropic openai fastapi uvicorn python-dotenv pydantic
      websockets feedparser python-multipart pymupdf setuptools
      google-auth google-auth-oauthlib google-api-python-client
    ]);
  in {
    description = "LLM Interface web UI";
    after = [ "network.target" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = username;
      WorkingDirectory = "/home/${username}/claude-wrapper/claudepilled";
      ExecStart = "${python}/bin/python -m llm_interface.server";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = "PYTHONPATH=/home/${username}/claude-wrapper/claudepilled:/home/${username}/briefing";
    };
  };

  # TaskChampion sync server — enables Taskwarrior sync with TaskChamp (iOS)
  systemd.services.taskchampion-sync-server = {
    description = "TaskChampion sync server";
    after = [ "network.target" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = username;
      ExecStart = "${pkgs.taskchampion-sync-server}/bin/taskchampion-sync-server --listen 0.0.0.0:9743 --data-dir /home/${username}/.local/share/taskchampion-sync-server";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Overnight research — processes research-queue.md via claude CLI at 2am daily
  systemd.services.overnight-research = {
    description = "Overnight research runner for ${vaultName} vault";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = "/home/${username}/.local/bin/overnight-research";
      Environment = [
        "HOME=/home/${username}"
        "PATH=/home/${username}/.local/bin:/run/current-system/sw/bin:/usr/bin:/bin"
      ];
      # Long-running (processes multiple questions up to stop-hour)
      TimeoutStartSec = "6h";
    };
  };
  systemd.timers.overnight-research = {
    description = "Run overnight research at 4am daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;  # catch up if machine was off at 4am
    };
  };

  # Publish pipeline — syncs Obsidian vault notes to Jekyll blog, every 30 min
  systemd.services.publish-blog = {
    description = "Publish Obsidian notes to intentionallydense Jekyll blog";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      WorkingDirectory = "/home/${username}/intentionallydense.github.io";
      ExecStart = "${pkgs.python3}/bin/python3 publish.py --go --push";
      Environment = [
        "HOME=/home/${username}"
        "PATH=/run/current-system/sw/bin:/usr/bin:/bin"
        "OBSIDIAN_VAULT=/home/${username}/Documents/Obsidian/${vaultName}"
      ];
    };
  };
  systemd.timers.publish-blog = {
    description = "Publish blog every 30 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* *:00,30:00";
      Persistent = true;
    };
  };

  # SSH (only reachable over Tailscale via trustedInterfaces above)
  # Port 22: handled by Tailscale SSH (identity-based auth)
  # Port 2200: regular sshd for Colab reverse tunnel (key-based auth,
  #   bypasses Tailscale SSH which intercepts port 22)
  services.openssh = {
    enable = true;
    ports = [ 22 2200 ];
  };

  networking.nameservers = [ "1.1.1.1" "8.8.8.8" "8.8.4.4" ];

}
