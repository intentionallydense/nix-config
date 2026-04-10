# Music server stack: Navidrome streaming + slskd downloads + beets tagging.
# Navidrome streams the organized library over Subsonic API (mobile: Amperfy/Symfonium).
# slskd provides headless Soulseek access for downloading.
# music-shelf is a unified search UI across library and Soulseek.
# Auto-import watches incoming/ and processes downloads through beets.
# aotd-download fetches the daily album-of-the-day from the briefing system.
# Used by: carbon.
{ pkgs, config, username, ... }:
let
  musicDir = "/home/${username}/music_library";
  scriptsDir = "${musicDir}/scripts";

  # Python environment for aotd-download and music-shelf
  musicPython = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
  ]);
in
{
  # --- Navidrome: music streaming server (Subsonic API) ---
  # Web UI at :4533, mobile access via Amperfy/Symfonium/DSub.
  # Last.fm scrobbling: enable in Navidrome web UI > user settings > link Last.fm account.
  # The server-side API key is set below; per-user linking happens in the UI.
  services.navidrome = {
    enable = true;
    openFirewall = true;
    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = "${musicDir}/library";
      DataFolder = "/var/lib/navidrome";
      ScanSchedule = "@every 5m";
      # Last.fm scrobbling — disabled until API key is obtained.
      # To enable: get an API key at https://www.last.fm/api/account/create,
      # put ND_LASTFM_APIKEY and ND_LASTFM_SECRET in ~/.config/navidrome/env,
      # set these to true, rebuild, then link your account in the Navidrome web UI.
      LastFM.Enabled = false;
    };
  };
  # Navidrome and slskd need to read/write fluoride's music dirs
  users.users.navidrome.extraGroups = [ "media" ];
  users.users.slskd.extraGroups = [ "media" ];

  # Both upstream modules set ProtectHome=yes, which hides /home entirely
  # and breaks access to music dirs. Override to allow access.
  systemd.services.navidrome.serviceConfig.ProtectHome = pkgs.lib.mkForce false;
  systemd.services.slskd.serviceConfig.ProtectHome = pkgs.lib.mkForce false;

  # Ensure home dir is traversable by media group services (navidrome, slskd).
  # Without o+x, services can't reach music_library/ even with correct group perms.
  systemd.tmpfiles.rules = [
    "d /home/${username} 0701 ${username} users -"
  ];

  # --- sops templates: compose secrets into env files for services ---
  sops.templates."slskd-env".content = ''
    SLSKD_SLSK_USERNAME=${config.sops.placeholder.slskd_slsk_username}
    SLSKD_SLSK_PASSWORD=${config.sops.placeholder.slskd_slsk_password}
    SLSKD_API_KEY=${config.sops.placeholder.slskd_api_key}
    SLSKD_USERNAME=${config.sops.placeholder.slskd_web_username}
    SLSKD_PASSWORD=${config.sops.placeholder.slskd_web_password}
  '';
  sops.templates."music-shelf-env".content = ''
    NAVIDROME_URL=http://localhost:4533
    NAVIDROME_USER=${config.sops.placeholder.navidrome_user}
    NAVIDROME_PASS=${config.sops.placeholder.navidrome_pass}
    SLSKD_URL=http://localhost:5030
    SLSKD_API_KEY=${config.sops.placeholder.slskd_api_key}
  '';

  # --- slskd: headless Soulseek client ---
  # Web UI at :5030, downloads to incoming/, shares library/ back to the network.
  # Credentials managed by sops-nix (see sops.templates above).
  services.slskd = {
    enable = true;
    openFirewall = true;
    domain = null; # No nginx reverse proxy — accessed directly over Tailscale
    environmentFile = config.sops.templates."slskd-env".path;
    settings = {
      directories = {
        downloads = "${musicDir}/incoming";
        incomplete = "${musicDir}/incoming/.incomplete";
      };
      shares = {
        directories = [ "${musicDir}/library" ];
      };
    };
  };

  # --- Packages: beets + audio tools ---
  # All beets plugins are enabled by default in nixpkgs; config.yaml controls which ones activate.
  environment.systemPackages = [
    pkgs.beets
    pkgs.ffmpeg
    pkgs.chromaprint  # AcoustID fingerprinting (fpcalc)
    musicPython
  ];

  # --- music-shelf: unified search web UI ---
  # Single search bar for library (Navidrome) + Soulseek (slskd).
  # One-click download from Soulseek, auto-import handles the rest.
  systemd.services.music-shelf = {
    description = "music-shelf — unified library + Soulseek search";
    after = [ "network.target" "navidrome.service" "slskd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = username;
      WorkingDirectory = "${musicDir}/music-shelf";
      ExecStart = "${musicPython}/bin/python -m uvicorn server:app --host 0.0.0.0 --port 4534";
      Restart = "on-failure";
      RestartSec = 5;
      # Credentials managed by sops-nix (see sops.templates above)
      EnvironmentFile = config.sops.templates."music-shelf-env".path;
    };
  };

  # --- Auto-import: polls incoming/ every 15 minutes ---
  # Runs music-import when new downloads land. Handles the convert → quality gate → beet import pipeline.
  systemd.services.music-auto-import = {
    description = "Auto-import music from incoming/ to library/";
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = "${scriptsDir}/music-import";
      Environment = [
        "HOME=/home/${username}"
        "PATH=/run/current-system/sw/bin"
      ];
    };
  };
  systemd.timers.music-auto-import = {
    description = "Run music-import every 15 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* *:00,15,30,45:00";
      Persistent = true;
    };
  };

  # --- AOTD download: fetches today's album-of-the-day ---
  # Reads the briefing system's AOTD pointer, searches slskd, downloads, imports.
  # Runs at 7am daily (after briefing assembles at 6:30am).
  systemd.services.aotd-download = {
    description = "Download today's album-of-the-day from Soulseek";
    after = [ "network-online.target" "slskd.service" ];
    wants = [ "network-online.target" ];
    requires = [ "slskd.service" ];  # don't run if slskd isn't up
    serviceConfig = {
      Type = "oneshot";
      User = username;
      # Wait 30s for slskd to connect and log in to the Soulseek network
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 30";
      ExecStart = "${musicPython}/bin/python ${scriptsDir}/aotd-download";
      Environment = [
        "HOME=/home/${username}"
        "PATH=/run/current-system/sw/bin"
      ];
      EnvironmentFile = config.sops.templates."slskd-env".path;
      # Generous timeout — slskd searches + downloads can take a while
      TimeoutStartSec = "45min";
    };
  };
  systemd.timers.aotd-download = {
    description = "Fetch album-of-the-day at 7am daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 07:00:00";
      Persistent = true;  # catch up if machine was asleep
    };
  };

  # Open music-shelf port in firewall (Tailscale-gated like everything else)
  networking.firewall.allowedTCPPorts = [ 4534 ];
}
