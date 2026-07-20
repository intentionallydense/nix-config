# Book/reading server stack: Calibre-Web library UI + Kobo plug-in sync.
# calibre-web serves the calibre library at :8083 (tailnet-only via firewall)
# for browsing, uploading from any device, and metadata editing.
# kobo-sync pushes books tagged 'to-sync' to a Kobo when plugged in via USB.
# Used by: tin. (The carbon-era kobo-briefing kepub builder was removed
# 2026-07-18 — briefing-coupled, gone with carbon; redo lands with Phase 2.
# History: `fleet-final` tag.)
{
  pkgs,
  lib,
  config,
  username,
  bookLibraryDir,
  ...
}:
let
  # Per-host via specialArgs (flake.nix *Settings): carbon keeps the legacy
  # in-$HOME layout (/home/fluoride/book_library); tin uses /srv/media/books.
  bookDir = bookLibraryDir;
  libraryInHome = lib.hasPrefix "/home/" bookDir;
  # NB: no spaces in this path. systemd splits ReadWritePaths on whitespace,
  # so "Calibre Library" gets truncated and fails namespace setup with
  # `status=226/NAMESPACE`. Calibre doesn't care what the dir is called.
  libraryDir = "${bookDir}/library";
  scriptsDir = "${bookDir}/scripts";
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
    openFirewall = false; # tailnet-only via trustedInterfaces (closes 8084 on LAN)
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
  # calibre-web user needs to read/write the book library.
  # Reuses the existing media group (also used by navidrome/jellyfin/slskd).
  users.users.calibre-web.extraGroups = [ "media" ];
  # Upstream module sets ProtectHome=yes, which hides /home — only punch
  # through when the library actually lives in /home (carbon's legacy layout).
  # Pattern matches navidrome/slskd in modules/server/music.
  systemd.services.calibre-web.serviceConfig.ProtectHome = lib.mkIf libraryInHome (lib.mkForce false);
  # ReadWritePaths needed either way (upstream sandboxing refuses writes
  # outside its own state dirs otherwise).
  systemd.services.calibre-web.serviceConfig.ReadWritePaths = [ libraryDir ];
  # Library outside /home: setgid media dir (list is empty on carbon's
  # in-$HOME layout, where the dir predates the module).
  systemd.tmpfiles.rules = lib.optionals (!libraryInHome) [
    "d ${bookDir} 2775 ${username} media -"
  ];

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

  # --- Packages: calibre CLI, kepubify, notify-send ---
  environment.systemPackages = [
    pkgs.calibre        # calibredb, ebook-convert
    pkgs.kepubify       # .epub → .kepub.epub for stock-firmware kobos
    pkgs.libnotify      # notify-send, used by kobo-sync for desktop notifications
  ];

  # --- kobo-sync: push 'to-sync' tagged books to Kobo on USB plug-in ---
  # Match the Kobo's user-facing partition by FS label ("KOBOeReader").
  # Same shape as mp3-sync's UUID-match in modules/music — udev fires the
  # systemd service, the service runs the python sync script as the user.
  # (Formerly routed through kobo-briefing first; that unit left with carbon,
  # so udev now triggers kobo-sync directly.)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="KOBOeReader", TAG+="systemd", ENV{SYSTEMD_WANTS}+="kobo-sync.service"
  '';

  systemd.services.kobo-sync = {
    description = "Sync tagged books from Calibre library to Kobo ereader";
    # Block device might still be settling when udev fires; the script waits
    # for the mount itself, but give the filesystem a beat.
    # Script silently no-ops if the kobo isn't actually present.
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
