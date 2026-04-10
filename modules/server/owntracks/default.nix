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

  # Open ports for Tailscale access
  networking.firewall.allowedTCPPorts = [ 8083 ];
}
