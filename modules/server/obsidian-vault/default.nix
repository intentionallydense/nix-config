# Headless Obsidian — full-vault Sync replica on the 24/7 box (Phase 2, first
# piece; landed 2026-07-04). Gives the fleet an always-on vault node so the
# vault-coupled automation (overnight-research, briefing, publish-blog) has a
# reliable home again — this is what carbon was, done deliberately this time.
#
# Design notes:
# - Obsidian is Electron; no headless mode exists. It runs under xvfb-run on a
#   fixed display (:99) so the on-demand VNC unit can attach for GUI sessions.
#   xvfb-run also gives the display an auth cookie — do NOT swap this for a
#   bare Xvfb unit (cookieless X lets any local user read the display).
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
# - VNC is -nopw on 0.0.0.0: house posture ("the firewall is the gate, not the
#   bind address") — only tailscale0 is trusted, public NIC exposes nothing.
#   It's also manual-start only (no wantedBy), so it's normally not running.
# - No sync-health watchdog yet: Restart=always covers crashes, but a wedged
#   sync is invisible. Wire a real check (last-sync introspection → ntfy) when
#   overnight-research lands, since that's the first thing that'll care.
{ pkgs, username, ... }:
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
    environment.HOME = "/home/${username}";
    serviceConfig = {
      ExecStart = obsidianHeadless;
      User = username;
      Restart = "always";
      RestartSec = 15;
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
      # -auth guess finds xvfb-run's cookie; works because we run as the same user.
      ExecStart = "${pkgs.x11vnc}/bin/x11vnc -display :99 -auth guess -forever -shared -nopw";
      User = username;
    };
  };
}
