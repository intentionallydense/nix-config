# Mullvad egress for tin's IP-sensitive traffic. wireproxy (userspace WireGuard —
# no kernel interface, no routing-table changes, nothing else on the box is
# affected) exposes two local proxies from one tunnel:
#
#   SOCKS5 127.0.0.1:1080 → slskd's Soulseek connection (filesharing shouldn't
#                           originate from a raw datacenter IP)
#   HTTP   127.0.0.1:8888 → invidious-companion egress (googlevideo rejects
#                           Hetzner IPs at the stream-format level — potoken
#                           validation fails; tested 2026-06-12)
#
# Private key: sops `wireproxy/tin` — the "Classy Boar" Mullvad device, rotated
# 2026-06-12 (first key touched chat logs). Address/peer below are per-key /
# public metadata and fine in the clear. Exit: ch-zrh-wg-005 (Zurich, CH),
# Sylvia's choice 2026-06-12.
#
# Inbound: Mullvad has no port forwarding (removed 2023), so slskd runs
# unconnectable — connectable peers can still download from us (they accept,
# we initiate); mutually-firewalled pairs can't transfer. Accepted trade.
#
# Leak posture: slskd's Soulseek connection is proxy-only by config — if the
# tunnel is down it connects to nothing (refused on loopback), it never falls
# back to the raw NIC. Ordering below is best-effort niceness, not the safety
# mechanism. NB slskd has been observed not to retry logins aggressively; if
# the tunnel bounces, `systemctl restart slskd`.
#
# Used by: tin (assumes modules/server/music + modules/server/invidious are
# imported — it reaches into slskd settings and the companion container).
{ pkgs, lib, ... }:
let
  tunnel = {
    # Mullvad device "Classy Boar" — in-tunnel addresses assigned to this key.
    address = "10.67.241.173/32,fc00:bbbb:bbbb:bb01::4:f1ac/128";
    # ch-zrh-wg-005 — verified against api.mullvad.net relay list 2026-06-12.
    publicKey = "dV/aHhwG0fmp0XuvSvrdWjCtdyhPDDFiE/nuv/1xnRM=";
    endpoint = "193.32.127.70:51820";
    exit = "ch-zrh-wg-005 (Zurich, CH)";
  };
  socksPort = 1080;
  httpPort = 8888;

  # Render the config (with the sops-decrypted key) into the unit's private
  # RuntimeDirectory, then exec wireproxy. Same pattern as the silicon-nixos
  # wireproxy module, system-service flavour.
  launcher = pkgs.writeShellScript "wireproxy-mullvad" ''
    set -euo pipefail
    secret="/run/secrets/wireproxy/tin"
    conf="$RUNTIME_DIRECTORY/mullvad.conf"
    if [ ! -f "$secret" ]; then
      echo "wireproxy-mullvad: sops secret $secret not present" >&2
      exit 1
    fi
    umask 077
    printf '%s\n' \
      "# wireproxy: Mullvad egress — ${tunnel.exit}" \
      "[Interface]" \
      "PrivateKey = $(cat "$secret")" \
      "Address = ${tunnel.address}" \
      "DNS = 10.64.0.1" \
      "" \
      "[Peer]" \
      "PublicKey = ${tunnel.publicKey}" \
      "Endpoint = ${tunnel.endpoint}" \
      "AllowedIPs = 0.0.0.0/0,::0/0" \
      "" \
      "[Socks5]" \
      "BindAddress = 127.0.0.1:${toString socksPort}" \
      "" \
      "[http]" \
      "BindAddress = 127.0.0.1:${toString httpPort}" \
      > "$conf"
    exec ${pkgs.wireproxy}/bin/wireproxy -c "$conf"
  '';
in
{
  sops.secrets."wireproxy/tin" = { }; # root-only; the launcher reads it

  systemd.services.wireproxy-mullvad = {
    description = "wireproxy: Mullvad egress via ${tunnel.exit} (SOCKS5 :${toString socksPort}, HTTP :${toString httpPort})";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "wireproxy-mullvad";
      ExecStart = launcher;
      Restart = "on-failure";
      RestartSec = 5;
      # Runs as root (to read the sops secret); locked down otherwise.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  # --- slskd: Soulseek connection through the tunnel (SOCKS5) ---
  services.slskd.settings.soulseek.connection.proxy = {
    enabled = true;
    address = "127.0.0.1";
    port = socksPort;
  };
  systemd.services.slskd = {
    after = [ "wireproxy-mullvad.service" ];
    wants = [ "wireproxy-mullvad.service" ];
  };

  # --- invidious-companion: YouTube egress through the tunnel (HTTP) ---
  # Host networking so the container can reach the host-loopback proxy;
  # companion then binds host 127.0.0.1:8282 directly (loopback-only, same
  # exposure as the old bridge + port-map posture).
  virtualisation.oci-containers.containers.invidious-companion = {
    ports = lib.mkForce [ ];
    extraOptions = [ "--network=host" ];
    environment = {
      HOST = lib.mkForce "127.0.0.1";
      # Companion's config reads bare `PROXY` (explicit Deno.env.get) — the
      # NETWORKING_* spelling is set too in case the mapping changes upstream;
      # whichever is unknown gets ignored. Verify in the container's startup
      # "Loaded Configuration" dump: networking.proxy must show this URL.
      PROXY = "http://127.0.0.1:${toString httpPort}";
      NETWORKING_PROXY = "http://127.0.0.1:${toString httpPort}";
    };
  };
  systemd.services.podman-invidious-companion = {
    after = [ "wireproxy-mullvad.service" ];
    wants = [ "wireproxy-mullvad.service" ];
  };
}
