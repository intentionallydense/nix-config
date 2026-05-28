# Book/reading server stack: Calibre-Web library UI + Kobo plug-in sync.
# calibre-web serves the calibre library at :8083 (tailnet-only via firewall)
# for browsing, uploading from any device, and metadata editing.
# kobo-sync pushes books tagged 'to-sync' to a Kobo when plugged in via USB.
# Used by: carbon.
{
  pkgs,
  config,
  username,
  ...
}:
let
  bookDir = "/home/${username}/book_library";
  # NB: no spaces in this path. systemd splits ReadWritePaths on whitespace,
  # so "Calibre Library" gets truncated and fails namespace setup with
  # `status=226/NAMESPACE`. Calibre doesn't care what the dir is called.
  libraryDir = "${bookDir}/library";
  scriptsDir = "${bookDir}/scripts";
  # Python env for kobo-briefing — needs trafilatura for FT readability extraction.
  # The `briefing` module itself is pip-installed in ~/miniconda3/envs/claude-ai
  # but we use a nix-built Python here for system-service determinism; the briefing
  # package is found via PYTHONPATH pointing at /home/${username}/briefing.
  kobo-python = pkgs.python313.withPackages (ps: with ps; [
    trafilatura
    feedparser
    certifi
  ]);
in
{
  # --- Calibre-Web: book library web UI ---
  # First-run admin: admin / admin123 — log in and change ASAP.
  # Listens on 0.0.0.0 but firewall trusts tailscale0 only, so it's tailnet-only.
  # Reachable as http://carbon.<tailnet>.ts.net:8083 from phone / silicon / wherever.
  services.calibre-web = {
    enable = true;
    # nixpkgs ships wand 0.7.0, but calibre-web 0.6.27b0's wheel pins
    # `wand<0.7.0,>=0.4.4`. Upstream's pythonRelaxDeps list missed `wand`,
    # so the build fails on pythonRuntimeDepsCheck. Patch it locally until
    # nixpkgs catches up.
    package = pkgs.calibre-web.overridePythonAttrs (old: {
      pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "wand" ];
    });
    openFirewall = true;
    listen.ip = "0.0.0.0";
    # 8083 is owntracks (see modules/server/owntracks). Calibre-web's default
    # is 8083, but we move it to 8084 to avoid the conflict.
    listen.port = 8084;
    options = {
      calibreLibrary = libraryDir;
      enableBookUploading = true;        # upload epubs from the web UI on any device
      enableBookConversion = true;       # format conversion via ebook-convert
      enableKepubify = true;             # let the web UI's "Send to Kobo" use kepubify too
    };
  };
  # calibre-web user needs to read/write fluoride's book_library.
  # Reuses the existing media group (also used by navidrome/jellyfin/slskd).
  users.users.calibre-web.extraGroups = [ "media" ];
  # Upstream module sets ProtectHome=yes, which hides /home — breaks library access.
  # Override matches the same pattern used for navidrome/slskd in modules/server/music.
  systemd.services.calibre-web.serviceConfig.ProtectHome = pkgs.lib.mkForce false;
  # Library lives in /home, so ReadWritePaths needs /home explicitly when
  # ProtectHome is off (systemd refuses to write under /home otherwise).
  systemd.services.calibre-web.serviceConfig.ReadWritePaths = [ libraryDir ];

  # --- Library bootstrap ---
  # Upstream calibre-web's ExecStartPre fails fast if metadata.db is absent,
  # so we run calibredb once before calibre-web to create an empty library on
  # first boot. Idempotent — no-op if metadata.db already exists.
  systemd.services.books-init = {
    description = "Bootstrap empty Calibre library on first run";
    wantedBy = [ "multi-user.target" ];
    before = [ "calibre-web.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      Group = "media";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "books-init" ''
        set -eu
        LIB="${libraryDir}"
        mkdir -p "$LIB"
        if [ ! -f "$LIB/metadata.db" ]; then
          echo "books-init: initializing empty calibre library at $LIB"
          # `calibredb list` against a missing library creates metadata.db
          ${pkgs.calibre}/bin/calibredb list --library-path="$LIB" >/dev/null
          chgrp -R media "$LIB" || true
          chmod -R g+rwX "$LIB" || true
        fi
      '';
    };
  };
  systemd.services.calibre-web.requires = [ "books-init.service" ];
  systemd.services.calibre-web.after = [ "books-init.service" ];

  # --- Packages: calibre CLI, kepubify, pandoc, notify-send ---
  environment.systemPackages = [
    pkgs.calibre        # calibredb, ebook-convert
    pkgs.kepubify       # .epub → .kepub.epub for stock-firmware kobos
    pkgs.pandoc         # markdown → epub, used by kobo-briefing post-processor
    pkgs.libnotify      # notify-send, used by kobo-sync for desktop notifications
  ];

  # --- sops template: paywalled-source cookies for kobo-briefing fetching ---
  # Browser-extracted session cookies; both last ~weeks. When fetches start
  # 401'ing or redirecting to /login, the kobo-briefing service logs loudly
  # — refresh the relevant cookie via browser devtools → `sops --set` →
  # rebuild.
  # `sops.secrets.<name>` must be declared before `sops.placeholder.<name>`
  # resolves — otherwise eval fails with `attribute '...' missing`.
  sops.secrets.ft_session_cookie = { };
  sops.secrets.acx_session_cookie = { };
  sops.templates."briefing-cookies-env" = {
    content = ''
      FT_SESSION_COOKIE=${config.sops.placeholder.ft_session_cookie}
      ACX_SESSION_COOKIE=${config.sops.placeholder.acx_session_cookie}
    '';
    owner = username;
  };

  # --- kobo-briefing: build today's briefing kepub with FT articles bundled ---
  # Reads ~/.briefing/briefings/<today>.md (produced by the 05:00 user-level
  # claude-briefing.service), fetches FT URLs with the sops-managed cookie,
  # readability-strips them, builds a kepub where the FT hyperlinks rewrite
  # to internal anchors that jump to the full article text bundled in the
  # same document, and adds the kepub to the calibre library tagged
  # 'briefing,to-sync' (replacing the previous day's entry).
  #
  # Runs at 05:15 — after claude-briefing's 05:00 cycle. Same timing pattern
  # as aotd-download in modules/server/music (separate-timer, no formal
  # systemd dependency on the user-level briefing service).
  systemd.services.kobo-briefing = {
    description = "Build today's briefing kepub with FT articles bundled";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    onFailure = [ "kobo-briefing-failure.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      WorkingDirectory = "/home/${username}/briefing";
      ExecStart = "${kobo-python}/bin/python -m briefing.kobo_edition";
      # If the kobo is currently present (either plug-in triggered us, or the
      # 05:15 timer fired while it's still plugged in), kick kobo-sync to
      # push the freshly-built briefing. --no-block so kobo-briefing.service
      # finishes before kobo-sync starts (avoids ExecStartPost waiting on it).
      ExecStartPost = pkgs.writeShellScript "trigger-kobo-sync-if-present" ''
        if [ -L /dev/disk/by-label/KOBOeReader ]; then
          ${pkgs.systemd}/bin/systemctl start --no-block kobo-sync.service
        fi
      '';
      EnvironmentFile = config.sops.templates."briefing-cookies-env".path;
      Environment = [
        "HOME=/home/${username}"
        "PATH=${pkgs.pandoc}/bin:${pkgs.kepubify}/bin:${pkgs.calibre}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin"
        "PYTHONPATH=/home/${username}/briefing"
        # notify-send needs the user session bus to reach the desktop
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      ];
      TimeoutStartSec = "20min";
    };
  };

  # Backstop for hard crashes that exit before the script can notify itself.
  # The script's own try/except handles normal error paths.
  systemd.services.kobo-briefing-failure = {
    description = "Record kobo-briefing systemd-level failure";
    serviceConfig = {
      Type = "oneshot";
      User = username;
      Environment = [
        "HOME=/home/${username}"
        "PATH=/run/current-system/sw/bin"
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      ];
      ExecStart = pkgs.writeShellScript "kobo-briefing-failure" ''
        ${pkgs.libnotify}/bin/notify-send -u critical -a kobo-briefing \
          "Briefing rebuild FAILED" \
          "Service crashed — journalctl -u kobo-briefing" || true
      '';
    };
  };

  systemd.timers.kobo-briefing = {
    description = "Build today's briefing kepub at 05:15 daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:15:00";
      Persistent = true;
    };
  };

  # --- kobo-sync: push 'to-sync' tagged books to Kobo on USB plug-in ---
  # Match the Kobo's user-facing partition by FS label ("KOBOeReader").
  # Same shape as mp3-sync's UUID-match in modules/server/music — udev fires the
  # systemd service, the service runs the python sync script as fluoride.
  # Plug-in chain: udev → kobo-briefing → (via ExecStartPost) kobo-sync.
  # Routing through briefing first means today's kepub is always fresh as of
  # plug-in time. And it doubles as a way for the 05:15 daily timer to push
  # the new briefing automatically if the kobo happens to still be plugged
  # in — kobo-sync's no-device guard makes a 05:15-with-no-kobo a no-op.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="KOBOeReader", TAG+="systemd", ENV{SYSTEMD_WANTS}+="kobo-briefing.service"
  '';

  systemd.services.kobo-sync = {
    description = "Sync tagged books from Calibre library to Kobo ereader";
    # Block device might still be settling when udev fires; the script waits
    # for the mount itself, but give the filesystem a beat.
    # Triggered only via kobo-briefing's ExecStartPost (single entry path).
    # Script silently no-ops if the kobo isn't actually present — so a 05:15
    # timer fire with no kobo connected is harmless.
    after = [ "local-fs.target" ];
    onFailure = [ "kobo-sync-failure.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = "${scriptsDir}/kobo-sync";
      Environment = [
        "HOME=/home/${username}"
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin"
        # notify-send and udisksctl need the user session bus
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      ];
      TimeoutStartSec = "30min";   # generous for the first push
    };
  };

  # Fallback failure handler — only fires if kobo-sync.service crashes BEFORE
  # the script writes its own status (hard exec error, OOM). The script's own
  # fail() handles normal error paths.
  systemd.services.kobo-sync-failure = {
    description = "Record kobo-sync systemd-level failure";
    serviceConfig = {
      Type = "oneshot";
      User = username;
      Environment = [
        "HOME=/home/${username}"
        "PATH=/run/current-system/sw/bin"
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      ];
      ExecStart = pkgs.writeShellScript "kobo-sync-failure" ''
        set -u
        STATEDIR="$HOME/.local/state/kobo-sync"
        mkdir -p "$STATEDIR"
        # Don't clobber a recent status the script already wrote — only
        # backstop when the script crashed before writing anything fresh.
        if [ -f "$STATEDIR/last-status.json" ] && \
           [ $(( $(date +%s) - $(stat -c %Y "$STATEDIR/last-status.json") )) -lt 60 ]; then
          exit 0
        fi
        cat > "$STATEDIR/last-status.json" <<EOF
        {"status":"systemd_failure","timestamp":"$(date -Iseconds)","error":"kobo-sync.service exited non-zero; see: journalctl -u kobo-sync"}
        EOF
        ${pkgs.libnotify}/bin/notify-send -u critical -a kobo-sync \
          "Kobo sync FAILED" \
          "Service crashed — journalctl -u kobo-sync" || true
      '';
    };
  };
}
