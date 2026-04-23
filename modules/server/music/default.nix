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

  # Ensure home dir is traversable by named-user ACL entries (navidrome, slskd).
  # Mode 0710 (not 0701!) is critical: POSIX ACL aliases the group perm to the
  # mask, and the mask AND's named-user entries. Mode 0701 would give mask=---,
  # killing `user:slskd:--x` / `user:navidrome:--x` → services can't traverse.
  # 0710 gives mask=--x which preserves those entries. Pairs with homeMode="0710"
  # in hosts/common.nix, which fixes the same problem on the update-users-groups
  # activation path.
  systemd.tmpfiles.rules = [
    "d /home/${username} 0710 ${username} users -"
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
  sops.templates."mp3-sync-env" = {
    content = ''
      NAVIDROME_URL=http://localhost:4533
      NAVIDROME_USER=${config.sops.placeholder.navidrome_user}
      NAVIDROME_PASS=${config.sops.placeholder.navidrome_pass}
    '';
    owner = username;  # mp3-sync.service runs as fluoride
  };

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
    pkgs.libnotify    # notify-send, used by mp3-sync for desktop notifications
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
  # EnvironmentFile=mp3-sync-env gives music-import the NAVIDROME_URL/USER/PASS
  # it needs to auto-star freshly-imported albums via star-new-albums.
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
      EnvironmentFile = config.sops.templates."mp3-sync-env".path;
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
      # slskd-env: SLSKD_API_KEY for search/download.
      # mp3-sync-env: NAVIDROME creds for the music-import star-new-albums step.
      EnvironmentFile = [
        config.sops.templates."slskd-env".path
        config.sops.templates."mp3-sync-env".path
      ];
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

  # --- mp3-sync: sync curated music subset to Fiio Echo Mini on plug-in ---
  # Selection: starred albums ∪ albums-in-Navidrome-playlist "echo".
  # Trigger: udev matches the 30GB SD card inside the Echo Mini (FS UUID
  # 36F9-1807, label "NO NAME") when it appears, which fires mp3-sync.service.
  # The Echo Mini also exposes a 7GB internal flash (UUID 6645-DD6E, label
  # "ECHO MINI") — we intentionally ignore that one: too small for a growing
  # curated set. The device itself is 071b:3203 (ROCK MP3).
  # Failures: layer 1 = notify-send from the script; layer 2 = status JSON at
  # ~/.local/state/mp3-sync/last-status.json; layer 3 = OnFailure helper below
  # catches crashes before the script writes its own status.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="36F9-1807", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mp3-sync.service"
  '';

  systemd.services.mp3-sync = {
    description = "Sync curated music to Fiio Echo Mini SD card";
    # Block device might still be settling when udev fires — the script waits
    # for the mount itself, but give the filesystem a beat.
    after = [ "local-fs.target" ];
    onFailure = [ "mp3-sync-failure.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = "${scriptsDir}/mp3-sync";
      EnvironmentFile = config.sops.templates."mp3-sync-env".path;
      Environment = [
        "HOME=/home/${username}"
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin"
        # Needed so notify-send and udisksctl find the user session bus
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      ];
      TimeoutStartSec = "30min";  # first sync may copy gigabytes
    };
  };

  # Fallback failure handler — only fires if mp3-sync.service exits non-zero
  # *before* the script itself wrote a status (hard crash / OOM / exec error).
  # The script's own fail() handles normal error paths.
  systemd.services.mp3-sync-failure = {
    description = "Record mp3-sync systemd-level failure";
    serviceConfig = {
      Type = "oneshot";
      User = username;
      Environment = [
        "HOME=/home/${username}"
        "PATH=/run/current-system/sw/bin"
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      ];
      ExecStart = pkgs.writeShellScript "mp3-sync-failure" ''
        set -u
        STATEDIR="$HOME/.local/state/mp3-sync"
        mkdir -p "$STATEDIR"
        # Don't clobber a status the script already wrote — only backstop when
        # the script crashed before writing anything recent (>60s stale).
        if [ -f "$STATEDIR/last-status.json" ] && \
           [ $(( $(date +%s) - $(stat -c %Y "$STATEDIR/last-status.json") )) -lt 60 ]; then
          exit 0
        fi
        cat > "$STATEDIR/last-status.json" <<EOF
        {"status":"systemd_failure","timestamp":"$(date -Iseconds)","error":"mp3-sync.service exited non-zero; see: journalctl -u mp3-sync"}
        EOF
        ${pkgs.libnotify}/bin/notify-send -u critical -a mp3-sync \
          "Echo Mini sync FAILED" \
          "Service crashed — journalctl -u mp3-sync" || true
      '';
    };
  };
}
