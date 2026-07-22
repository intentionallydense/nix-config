# Headless Obsidian — full-vault Sync replica on the 24/7 box (Phase 2, first
# piece; landed 2026-07-04). Gives the fleet an always-on vault node so the
# vault-coupled automation (overnight-research, briefing, publish-blog) has a
# reliable home again — this is what carbon was, done deliberately this time.
#
# Design notes:
# - Obsidian is Electron; no headless mode exists. It runs under xvfb-run on a
#   fixed display (:99) so the on-demand VNC unit can attach for GUI sessions.
#   Honesty note: this xvfb-run variant creates an auth cookie but does NOT
#   pass -auth to Xvfb, so :99 accepts any local connection. Tolerated: the
#   box is single-tenant, and the service users are PrivateTmp-sandboxed away
#   from the /tmp/.X11-unix socket. Revisit if tin ever grows real users.
# - Sylvia accepted the full-vault-on-Hetzner exposure explicitly (2026-07-04):
#   whole vault, not a selective-sync subset. Vault path: ~/vault (0700 home).
# - One-time GUI setup (after first deploy):
#     1. tin:       systemctl start obsidian-vnc
#     2. germanium: open vnc://100.65.236.26:5900   (macOS Screen Sharing)
#     3. Obsidian:  sign in → Sync → connect remote vault → local path
#                   /home/iodide/vault → enable ALL file-type toggles
#                   (images/audio/video/PDF/other + vault config) — this is a
#                   full replica, not a notes-only mirror.
#     4. tin:       systemctl stop obsidian-vnc
# - VNC binds 0.0.0.0: house posture ("the firewall is the gate, not the bind
#   address") — only tailscale0 is trusted, public NIC exposes nothing. VNC
#   password "obsidian" (client-appeasement only, see below). Manual-start
#   only (no wantedBy), so it's normally not running.
# - Sync-health watchdog (added 2026-07-22): Restart=always covers crashes,
#   but a wedged sync is invisible from systemd. Every 10 min a root timer
#   checks the service is active AND the Electron process holds an established
#   TLS connection (Obsidian Sync rides a wss:// websocket; a wedged or
#   offline sync drops it) and pings healthchecks.io check `vault-sync`
#   (period 10 min, grace 30 min, alerts via ntfy). Honest limits: an
#   established socket proves connectivity, not that edits are flowing — but
#   it catches the real failure modes seen in practice: dead process, dead
#   Xvfb, dead network, hung Electron. Last-sync introspection can replace it
#   when overnight-research lands and gives us something that reads the vault.
{ pkgs, config, username, ... }:
let
  obsidianHeadless = pkgs.writeShellScript "obsidian-headless" ''
    export LIBGL_ALWAYS_SOFTWARE=1
    exec ${pkgs.dbus}/bin/dbus-run-session -- \
      ${pkgs.xvfb-run}/bin/xvfb-run -a -n 99 \
        -s "-screen 0 1600x1000x24 -nolisten tcp" \
        ${pkgs.obsidian}/bin/obsidian --disable-gpu
  '';
in
{
  # Headless box ships no fonts; without these the VNC session renders tofu.
  # CJK included — the vault has Chinese in it.
  fonts.packages = with pkgs; [
    dejavu_fonts
    noto-fonts
    noto-fonts-cjk-sans
  ];

  systemd.services.obsidian = {
    description = "Headless Obsidian (vault Sync replica) on Xvfb :99";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # dbus-run-session execs `dbus-daemon` by bare name — it must be on PATH.
    path = [ pkgs.dbus ];
    environment.HOME = "/home/${username}";
    serviceConfig = {
      ExecStart = obsidianHeadless;
      User = username;
      Restart = "always";
      RestartSec = 15;
    };
  };

  # --- sync-health watchdog (see header) ---
  sops.secrets.hc_vault_sync_url = {
    owner = "root";
    mode = "0400";
  };

  systemd.services.vault-sync-watchdog = {
    description = "Ping healthchecks when Obsidian Sync looks alive";
    path = with pkgs; [ coreutils curl iproute2 gnugrep systemd ];
    serviceConfig = {
      Type = "oneshot";
      # root: reads the 0400 hc URL; the socket check needs -p on another
      # user's process anyway.
      ExecStart = pkgs.writeShellScript "vault-sync-watchdog" ''
        set -uo pipefail
        systemctl is-active --quiet obsidian || exit 0
        # Obsidian Sync holds a wss:// websocket; electron with an
        # established :443 connection is our liveness signal.
        if ss -tnp state established '( dport = :443 )' | grep -q electron; then
          curl -fsS -m 10 -d "sync socket established" \
            "$(cat ${config.sops.secrets.hc_vault_sync_url.path})" >/dev/null || true
        fi
      '';
    };
  };

  systemd.timers.vault-sync-watchdog = {
    description = "Check Obsidian Sync liveness every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "10min";
      Persistent = false;
    };
  };

  # Manual-start only: `systemctl start obsidian-vnc` for GUI sessions
  # (initial Sync login, plugin fiddling), stop it when done.
  systemd.services.obsidian-vnc = {
    description = "x11vnc into the headless Obsidian display (manual start, tailnet-gated)";
    after = [ "obsidian.service" ];
    requires = [ "obsidian.service" ];
    environment.HOME = "/home/${username}";
    serviceConfig = {
      # No -auth: Xvfb on :99 runs cookieless (see header note), and -auth guess
      # breaks in the sparse unit PATH (shells out to awk/netstat).
      # The VNC password is NOT a security boundary (the tailnet gate is) — it
      # exists only because macOS Screen Sharing refuses SecurityType=None.
      # Plaintext in the store/ps is accepted on this single-tenant box.
      ExecStart = "${pkgs.x11vnc}/bin/x11vnc -display :99 -forever -shared -passwd obsidian";
      User = username;
    };
  };
}
