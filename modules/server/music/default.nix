# Music server stack: Navidrome streaming + slskd downloads + beets tagging.
# Navidrome streams the organized library over Subsonic API (mobile: Amperfy/Symfonium).
# slskd provides headless Soulseek access for downloading.
# music-shelf is a unified search UI across library and Soulseek.
# Auto-import watches incoming/ and processes downloads through beets.
# aotd-download fetches the daily album-of-the-day from the briefing system.
# Used by: carbon, tin.
{ pkgs, lib, config, username, musicLibraryDir, ... }:
let
  # Per-host via specialArgs (flake.nix *Settings): carbon keeps the legacy
  # in-$HOME layout (/home/fluoride/music_library); tin uses /srv/media/music.
  musicDir = musicLibraryDir;
  # The /home special-casing below (traversal ACLs, ProtectHome punch-through)
  # only applies when the library actually lives inside a home directory.
  libraryInHome = lib.hasPrefix "/home/" musicDir;
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
    openFirewall = false; # tailnet-only via trustedInterfaces (closes 4533 on LAN)
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
      # Don't split a single album folder into multiple "release" records based
      # on differing per-track metadata (e.g. some tracks with MusicBrainz IDs,
      # others without; mixed encoder TXXX leftovers from format conversion).
      # Group strictly by (album, albumartist). Cost: multi-disc box sets won't
      # be visually grouped — fine for this library, which is mostly mp3 albums.
      Scanner.GroupAlbumReleases = false;
    };
  };
  # Navidrome and slskd need to read/write the music library
  users.users.navidrome.extraGroups = [ "media" ];
  users.users.slskd.extraGroups = [ "media" ];

  # Both upstream modules set ProtectHome=yes, which hides /home entirely.
  # Only punch through when the library actually lives in /home (carbon's
  # legacy layout); with a /srv library the sandboxing stays intact.
  systemd.services.navidrome.serviceConfig.ProtectHome = lib.mkIf libraryInHome (lib.mkForce false);
  systemd.services.slskd.serviceConfig.ProtectHome = lib.mkIf libraryInHome (lib.mkForce false);

  systemd.tmpfiles.rules =
    if libraryInHome then [
      # Ensure home dir is traversable by named-user ACL entries (navidrome, slskd).
      # Mode 0710 (not 0701!) is critical: POSIX ACL aliases the group perm to the
      # mask, and the mask AND's named-user entries. Mode 0701 would give mask=---,
      # killing `user:slskd:--x` / `user:navidrome:--x` → services can't traverse.
      # 0710 gives mask=--x which preserves those entries. Pairs with homeMode="0710"
      # in hosts/common.nix, which fixes the same problem on the update-users-groups
      # activation path.
      "d /home/${username} 0710 ${username} users -"
    ] else [
      # Library outside /home: no traversal ACLs needed. Setgid media dir so
      # everything created inside stays group-accessible.
      "d ${musicDir} 2775 ${username} media -"
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

  # healthchecks.io ping URL for the AOTD dead-man's-switch. 0444: aotd-download
  # runs as the user and needs to read it; kept out of the public repo via sops.
  sops.secrets.hc_aotd_url.mode = "0444";

  # --- slskd: headless Soulseek client ---
  # Web UI at :5030, downloads to incoming/, shares library/ back to the network.
  # Credentials managed by sops-nix (see sops.templates above).
  services.slskd = {
    enable = true;
    # Tailnet-only. On eduroam we can't port-forward inbound 50300 (no control
    # over the gateway, and its NAT blocks unsolicited inbound), so opening the
    # Soulseek listener would expose it to the eduroam LAN for zero benefit —
    # slskd runs outbound-only either way (same reason qBittorrent is disabled
    # here). The web UI (5030) is likewise tailnet-only (domain = null below).
    # If carbon ever moves to a network you control: set openFirewall = true
    # AND forward 50300 on the router.
    openFirewall = false;
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
    pkgs.mpv          # used by aotd-play.service for wake-up album playback
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
      # Mirror of the kobo-briefing → kobo-sync chain: when music-import
      # finishes, if the Echo Mini SD card happens to be plugged in, push
      # any newly-imported (and freshly-starred) albums to it without
      # waiting for a replug. mp3-sync silently no-ops when not present.
      # `+` prefix runs this ExecStartPost with full privileges (ignoring
      # User=fluoride) — required so `systemctl start` on a system service
      # doesn't hit polkit's "interactive authentication required" wall.
      ExecStartPost = "+${pkgs.writeShellScript "trigger-mp3-sync-if-present" ''
        if [ -L /dev/disk/by-uuid/36F9-1807 ]; then
          ${pkgs.systemd}/bin/systemctl start --no-block mp3-sync.service
        fi
      ''}";
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
  # Runs at 05:30 daily — must come AFTER briefing (05:00) which advances the
  # AOTD index, and BEFORE aotd-play (06:50) which plays the downloaded album.
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
      # ExecStartPost runs only if the download succeeded. Ping healthchecks
      # FIRST (non-fatal `-`) so the dead-man signal isn't gated by the mp3-sync
      # trigger; then the Echo Mini push (the `+` runs it with full privileges,
      # ignoring User=fluoride, so `systemctl start` on a system service doesn't
      # hit polkit's "interactive authentication required" wall).
      ExecStartPost = [
        "-${pkgs.writeShellScript "hc-ping-aotd" ''
          ${pkgs.curl}/bin/curl -fsS -m 10 "$(cat ${config.sops.secrets.hc_aotd_url.path})" >/dev/null
        ''}"
        "+${pkgs.writeShellScript "trigger-mp3-sync-if-present" ''
          if [ -L /dev/disk/by-uuid/36F9-1807 ]; then
            ${pkgs.systemd}/bin/systemctl start --no-block mp3-sync.service
          fi
        ''}"
        # Morning receipt: push today's AOTD outcome (written by aotd-download to
        # ~/.briefing/aotd-last.txt) to the phone — a daily "reused / downloaded"
        # confirmation. Runs only on success: ExecStartPost is skipped when the
        # script exits non-zero, and those failures are already covered by the
        # hc-ping dead-man's-switch above. The `+` prefix runs it as root so it
        # can read the root-only ntfy topic secret shared with server/alerts.
        # Low priority + distinct title so it reads as an FYI, not an alarm.
        "+${pkgs.writeShellScript "aotd-receipt" ''
          body="$(${pkgs.coreutils}/bin/cat /home/${username}/.briefing/aotd-last.txt 2>/dev/null)"
          [ -n "$body" ] || exit 0
          ${pkgs.curl}/bin/curl -s -m 10 \
            -H "Title: ▶ Album of the day" \
            -H "Priority: low" \
            -H "Tags: musical_note" \
            -d "$body" \
            "$(cat ${config.sops.secrets.ntfy_alert_url.path})" || true
        ''}"
      ];
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
    description = "Fetch album-of-the-day at 05:30 daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:30:00";
      Persistent = true;  # catch up if machine was asleep
    };
  };

  # --- AOTD play: wake-up playback at 06:50 ---
  # Connects the Bluetooth speaker (猫王·小王子OTR), routes audio to it, and plays
  # today's downloaded album with a gentle volume ramp (10% → 60% over 3 min).
  # Reads the same briefing pointer that aotd-download used, so the played album
  # matches what was just fetched.
  # Quietly no-ops if the album isn't in the library yet (e.g. download still
  # running or failed) — silence is better than yesterday's audio.
  systemd.services.aotd-play = {
    description = "Play today's album-of-the-day on the Bluetooth speaker";
    after = [ "aotd-download.service" ];
    onFailure = [ "aotd-play-failure.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = "${musicPython}/bin/python ${scriptsDir}/aotd-play";
      Environment = [
        "HOME=/home/${username}"
        # bluetoothctl lives in /run/current-system/sw/bin; wpctl and mpv too
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin"
        # Required so wpctl/pw-cli reach the user's pipewire socket and
        # bluetoothctl talks to the system bus correctly under the user session
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
        # Forces UTF-8 so the Chinese-named sink parses cleanly under systemd's
        # otherwise-C locale
        "LANG=en_US.UTF-8"
        "LC_ALL=en_US.UTF-8"
      ];
      # Generous timeout — long albums + the 3-min volume ramp + any retries
      TimeoutStartSec = "120min";
    };
  };
  systemd.timers.aotd-play = {
    description = "Play album-of-the-day at 06:50 daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 06:50:00";
      # Persistent=false on purpose: if the machine was off and missed the
      # window, don't blast music at a surprise time when it boots later.
      Persistent = false;
    };
  };

  # Failure handler — fires (via onFailure on aotd-play above) whenever the
  # morning playback exits non-zero: speaker unreachable, BT sink never
  # appeared, mpv crash, etc. Pushes an immediate, actionable ntfy so a silent
  # wake-up miss becomes a "go power-cycle the speaker" nudge on your phone,
  # instead of being noticed days later. Mirrors the mp3-sync → mp3-sync-failure
  # pattern above.
  #
  # Runs as root (no User=) so it can read the root-only ntfy_alert_url secret
  # shared with modules/server/alerts. After alerting it clears aotd-play's
  # failed latch via reset-failed, so the generic 15-min carbon-alert-check
  # doesn't pile on a second, cryptic "failed units: aotd-play.service" push
  # (and re-fire it every 6h) for a one-shot morning hiccup this handler already
  # reported. Drop that last line if you'd rather the failure stay visible in
  # `systemctl --failed` as a breadcrumb.
  systemd.services.aotd-play-failure = {
    description = "Alert (ntfy) when aotd-play fails to play the morning album";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "aotd-play-failure" ''
        set -u
        reason="$(${pkgs.systemd}/bin/journalctl -u aotd-play.service -n 6 --no-pager -o cat 2>/dev/null \
                  | ${pkgs.gnugrep}/bin/grep -F '[aotd-play]' | tail -1)"
        [ -n "$reason" ] || reason="aotd-play.service failed — see: journalctl -u aotd-play"
        ${pkgs.curl}/bin/curl -s -m 10 \
          -H "Title: 🔇 Album-of-the-day didn't play" \
          -H "Priority: high" \
          -H "Tags: mute" \
          -d "$reason

Speaker likely off / asleep / wedged — power-cycle the 猫王 speaker, then:
  systemctl start aotd-play   (today's album is already in the library)" \
          "$(cat ${config.sops.secrets.ntfy_alert_url.path})" || true
        ${pkgs.systemd}/bin/systemctl reset-failed aotd-play.service || true
      '';
    };
  };

  # music-shelf (4534) is tailnet-only via trustedInterfaces — it binds 0.0.0.0
  # (see ExecStart --host) but the firewall only trusts tailscale0, so no LAN
  # opening is needed. (Removed allowedTCPPorts = [ 4534 ] 2026-06-01.)

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
