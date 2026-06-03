# Wireproxy — userspace WireGuard SOCKS5 proxies for Firefox profile isolation (NixOS port).
# Each Firefox profile routes through a dedicated Mullvad exit node via wireproxy. WireGuard
# private keys come from system sops (/run/secrets/wireproxy/<name>, owned by the user); each
# tunnel runs as a per-user systemd service exposing a local SOCKS5 port.
# NixOS counterpart of modules/darwin/wireproxy (which uses launchd). Used by: hosts/silicon/nixos.nix
{
  pkgs,
  lib,
  username,
  ...
}:
let
  # Mullvad WireGuard exit nodes — one per Firefox profile.
  # Ports match each profile's SOCKS5 / PAC settings.
  tunnels = {
    personal = {
      port = 1081;
      address = "10.69.28.158/32";
      publicKey = "5JMPeO7gXIbR5CnUa/NPNK4L5GqUnreF0/Bozai4pl4=";
      endpoint = "185.213.154.66:51820";
      exit = "se-got-wg-001 (Gothenburg, SE)";
    };
    sensitive = {
      port = 1082;
      address = "10.69.182.167/32";
      publicKey = "qcvI02LwBnTb7aFrOyZSWvg4kb7zNW9/+rS6alnWyFE=";
      endpoint = "193.32.127.67:51820";
      exit = "ch-zrh-wg-002 (Zurich, CH)";
    };
    academic = {
      port = 1083;
      address = "10.69.81.232/32";
      publicKey = "UrQiI9ISdPPzd4ARw1NHOPKKvKvxUhjwRjaI0JpJFgM=";
      endpoint = "193.32.249.66:51820";
      exit = "nl-ams-wg-001 (Amsterdam, NL)";
    };
    social = {
      port = 1084;
      address = "10.70.58.78/32,fc00:bbbb:bbbb:bb01::7:3a4d/128";
      publicKey = "JEuuPzZE8uE53OFhd3YFiZuwwANLqwmdXWMHPUbBwnk=";
      endpoint = "185.156.46.130:51820";
      exit = "us-qas-wg-101 (Ashburn, VA)";
    };
  };

  # Render the wireproxy config from the sops-decrypted key into the unit's private
  # RuntimeDirectory, then exec wireproxy. System sops decrypts at activation, so unlike
  # the darwin/launchd version this needs no wait-loop.
  mkLauncher =
    name: tunnel:
    pkgs.writeShellScript "wireproxy-${name}" ''
      set -euo pipefail
      secret="/run/secrets/wireproxy/${name}"
      conf="$RUNTIME_DIRECTORY/${name}.conf"
      if [ ! -f "$secret" ]; then
        echo "wireproxy-${name}: sops secret $secret not present" >&2
        exit 1
      fi
      umask 077
      printf '%s\n' \
        "# wireproxy: ${name} — ${tunnel.exit}" \
        "# SOCKS5 on 127.0.0.1:${toString tunnel.port}" \
        "" \
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
        "BindAddress = 127.0.0.1:${toString tunnel.port}" \
        > "$conf"
      exec ${pkgs.wireproxy}/bin/wireproxy -c "$conf"
    '';
in
{
  # WireGuard private keys — one system-sops secret per tunnel, readable by the user.
  sops.secrets = lib.mapAttrs' (
    name: _:
    lib.nameValuePair "wireproxy/${name}" {
      owner = username;
      mode = "0400";
    }
  ) tunnels;

  home-manager.sharedModules = [
    (
      { lib, ... }:
      {
        home.packages = [ pkgs.wireproxy ];

        # One per-user systemd service per tunnel.
        systemd.user.services = lib.mapAttrs' (
          name: tunnel:
          lib.nameValuePair "wireproxy-${name}" {
            Unit = {
              Description = "wireproxy: ${name} → ${tunnel.exit} (SOCKS5 :${toString tunnel.port})";
              After = [ "network-online.target" ];
            };
            Install.WantedBy = [ "default.target" ];
            Service = {
              Type = "simple";
              RuntimeDirectory = "wireproxy";
              ExecStart = "${mkLauncher name tunnel}";
              Restart = "on-failure";
              RestartSec = 5;
            };
          }
        ) tunnels;

        # PAC files for the profiles that keep Tailscale/local traffic direct (Personal, Academic);
        # everything else egresses through that profile's Mullvad SOCKS5.
        xdg.configFile = lib.genAttrs [ "firefox-pac/personal.pac" "firefox-pac/academic.pac" ] (
          path:
          let
            name = lib.removeSuffix ".pac" (lib.removePrefix "firefox-pac/" path);
            port = toString tunnels.${name}.port;
          in
          {
            text = ''
              // PAC for the "${name}" Firefox profile — Tailscale/local direct, else Mullvad SOCKS5.
              function FindProxyForURL(url, host) {
                  if (isInNet(host, "100.64.0.0", "255.192.0.0")) { return "DIRECT"; }
                  if (shExpMatch(host, "*.ts.net")) { return "DIRECT"; }
                  if (isPlainHostName(host) ||
                      host === "localhost" || host === "127.0.0.1" ||
                      isInNet(host, "10.0.0.0", "255.0.0.0") ||
                      isInNet(host, "172.16.0.0", "255.240.0.0") ||
                      isInNet(host, "192.168.0.0", "255.255.0.0")) {
                      return "DIRECT";
                  }
                  return "SOCKS5 127.0.0.1:${port}";
              }
            '';
          }
        );
      }
    )
  ];
}
