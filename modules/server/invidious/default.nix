# Invidious — privacy-respecting YouTube frontend, self-hosted on carbon.
# Accessed via Yattee (macOS/iOS) over Tailscale, using account-based
# subscription sync so the same sub list appears across devices.
#
# 2026 architecture note: Invidious has moved to a companion-based design.
# Video stream extraction now happens in `invidious-companion` (Deno app
# backed by youtube.js, actively maintained). The older `inv-sig-helper`
# is unmaintained upstream since 2025-07 and does not handle current
# YouTube player JS — we do NOT use it.
#
# Services:
#   - invidious (port 3001): web UI, account/sub management, feeds
#   - invidious-companion (127.0.0.1:8282, via podman): stream retrieval
#   - postgres "invidious" db (auto-provisioned alongside Immich's)
#
# Companion is pulled from quay.io/invidious/invidious-companion:latest
# because nixpkgs doesn't package it yet (Deno app). Updated by restarting
# the container, or by pinning a digest once stability matters.
#
# Access pattern: http://carbon:3001 over Tailscale. No HTTPS, no public
# domain — same as jellyfin (8096), immich (2283), grafana (3000).
# Companion's port is loopback-only; only invidious talks to it.
#
# The shared 16-char secret between Invidious and companion lives in
# /var/lib/invidious-companion/key (root-only, auto-generated on first
# boot). Two derivative files are written for the two services to read
# in their expected formats.
#
# Note: by upstream default the invidious service restarts every ~1h
# with ±5min jitter. Intentional, not a problem.
#
# Used by: carbon.
{ config, pkgs, lib, ... }:
let
  stateDir = "/var/lib/invidious-companion";
  keyFile = "${stateDir}/key";
  invidiousExtraFile = "${stateDir}/invidious-extra.json";
  companionEnvFile = "${stateDir}/companion.env";
in
{
  # Shared-secret provisioner. Runs once at boot; regenerates the two
  # derivative files from the persistent key every time (cheap and
  # self-healing if someone mucks with them).
  systemd.services.invidious-companion-secret = {
    description = "Provision invidious-companion shared secret";
    wantedBy = [ "multi-user.target" ];
    before = [ "invidious.service" "podman-invidious-companion.service" ];
    path = [ pkgs.pwgen pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      mkdir -p ${stateDir}
      chmod 0755 ${stateDir}
      if [[ ! -s ${keyFile} ]]; then
        pwgen -s 16 1 > ${keyFile}
        chmod 0400 ${keyFile}
      fi
      key="$(cat ${keyFile})"
      printf '{"invidious_companion_key": "%s"}\n' "$key" > ${invidiousExtraFile}
      printf 'SERVER_SECRET_KEY=%s\n' "$key" > ${companionEnvFile}
      # World-readable: both files' secret is scoped to a private service
      # only reachable over Tailscale. Good enough; revisit if the threat
      # model changes.
      chmod 0644 ${invidiousExtraFile} ${companionEnvFile}
    '';
  };

  services.invidious = {
    enable = true;
    port = 3001;
    address = "0.0.0.0"; # Access gated by Tailscale firewall (carbon config)

    database.createLocally = true;

    # Deprecated in 2026 — companion replaces it. Explicit false for clarity.
    sig-helper.enable = false;

    # Injects {"invidious_companion_key": "..."} at service-start time.
    extraSettingsFile = invidiousExtraFile;

    settings = {
      # carbon's stateVersion is 23.11 → module defaults db.user = "kemal".
      # Override to match db.dbname ("invidious") required by the
      # database.createLocally assertion.
      db.user = "invidious";

      registration_enabled = true;
      login_enabled = true;
      # Captcha breaks API-based auth (Yattee can't solve it). Private
      # instance behind tailscale, no drive-by-signup threat — safe to
      # disable. Browser signup worked fine with captcha on because
      # Sylvia solved it manually; disabling it lets Yattee log in too.
      captcha_enabled = false;
      popular_enabled = false;
      statistics_enabled = false;
      https_only = false;

      # Points Invidious at the companion running in the podman container.
      # The path "/companion" matches companion's default SERVER_BASE_PATH.
      invidious_companion = [
        { private_url = "http://127.0.0.1:8282/companion"; }
      ];
    };
  };

  # Ensure secret is ready and companion is up before Invidious starts.
  systemd.services.invidious = {
    after = [
      "invidious-companion-secret.service"
      "podman-invidious-companion.service"
    ];
    wants = [ "podman-invidious-companion.service" ];
  };

  # Companion container — port exposed only on loopback.
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  virtualisation.oci-containers = {
    backend = "podman";
    containers.invidious-companion = {
      image = "quay.io/invidious/invidious-companion:latest";
      ports = [ "127.0.0.1:8282:8282" ];
      environmentFiles = [ companionEnvFile ];
      environment = {
        HOST = "0.0.0.0"; # bind inside the container; host-side only 127.0.0.1
        PORT = "8282";
      };
      autoStart = true;
    };
  };

  networking.firewall.allowedTCPPorts = [ 3001 ];
}
