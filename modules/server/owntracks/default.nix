# OwnTracks Recorder — stores location data published by the OwnTracks phone app.
# HTTP endpoint and web UI both on port 8083.
# No NixOS service module exists, so this wraps ot-recorder in a systemd unit.
# Used by: carbon.
{ pkgs, ... }:
let
  dataDir = "/var/lib/owntracks";
in
{
  # ot-recorder: HTTP mode (no MQTT broker needed).
  # Phone app POSTs to http://<tailscale-ip>:8083/pub
  # Web UI (last known positions, tracks) at http://<tailscale-ip>:8083
  systemd.services.owntracks-recorder = {
    description = "OwnTracks Recorder";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      StateDirectory = "owntracks";
      # --port 0 disables MQTT (HTTP-only mode), topic "owntracks/#" is required but unused without MQTT
      ExecStart = "${pkgs.owntracks-recorder}/bin/ot-recorder --storage ${dataDir} --http-host 0.0.0.0 --http-port 8083 --doc-root ${pkgs.owntracks-recorder}/htdocs --port 0 owntracks/#";
      Restart = "on-failure";
      RestartSec = 5;

      # Hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  # OwnTracks (8083) is tailnet-only via trustedInterfaces — the recorder binds
  # 0.0.0.0 (--http-host above) but the firewall only trusts tailscale0, and the
  # phone POSTs to the Tailscale IP, so no LAN opening is needed. (Removed
  # allowedTCPPorts = [ 8083 ] 2026-06-01.)

  # Daily location-timeline generator. Runs at 05:00 local time, writes
  # claude/location/YYYY-MM-DD.md to the obsidian vault.
  # Script is at ~/.local/bin/owntracks-day (managed outside the flake;
  # if it's missing the timer just no-ops).
  systemd.services.owntracks-day = {
    description = "Generate yesterday's location timeline from OwnTracks data";
    after = [ "owntracks-recorder.service" "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "fluoride";
      ExecStart = "/home/fluoride/.local/bin/owntracks-day yesterday";
    };
    path = [ pkgs.python3 ];
  };

  systemd.timers.owntracks-day = {
    description = "Daily owntracks-day run at 05:00";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:00:00";
      Persistent = true;   # if missed (e.g. machine off), run on next boot
      Unit = "owntracks-day.service";
    };
  };
}
