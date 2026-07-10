# Mullvad egress for tin's IP-sensitive traffic. wireproxy (userspace WireGuard —
# no kernel interface, no routing-table changes, nothing else on the box is
# affected) exposes a local SOCKS5 proxy from one tunnel:
#
#   SOCKS5 127.0.0.1:1080 → slskd's Soulseek connection (filesharing shouldn't
#                           originate from a raw datacenter IP)
#
# (The HTTP proxy for invidious-companion was removed 2026-07-02 along with
# Invidious itself — playback was dead from the Hetzner DC IP regardless.)
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
# Used by: tin (assumes modules/server/music is imported — it reaches into
# slskd's settings to force its Soulseek connection through the SOCKS5 proxy).
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
      > "$conf"
    exec ${pkgs.wireproxy}/bin/wireproxy -c "$conf"
  '';
in
{
  sops.secrets."wireproxy/tin" = { }; # root-only; the launcher reads it

  systemd.services.wireproxy-mullvad = {
    description = "wireproxy: Mullvad egress via ${tunnel.exit} (SOCKS5 :${toString socksPort})";
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
}
