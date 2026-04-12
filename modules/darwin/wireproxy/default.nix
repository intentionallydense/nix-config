# Wireproxy — userspace WireGuard SOCKS5 proxies for Firefox profile isolation.
# Each Firefox profile routes through a dedicated Mullvad exit node via wireproxy.
# WireGuard private keys are decrypted from sops at activation time.
# Used by: hosts/silicon/default.nix
{ ... }:
let
  # Mullvad WireGuard exit nodes — one per Firefox profile.
  # Ports match the SOCKS5 proxy settings in each Firefox profile's about:config.
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
in
{
  home-manager.sharedModules = [
    (
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        configDir = "${config.xdg.configHome}/wireproxy";
        secretsDir = config.sops.defaultSymlinkPath;

        # Wrapper script that reads the sops-decrypted private key, generates
        # the wireproxy config, and execs wireproxy. This avoids the race
        # between sops-nix's async launchd decryption and wireproxy startup.
        mkLauncher =
          name: tunnel:
          pkgs.writeShellScript "wireproxy-${name}" ''
            set -euo pipefail
            secret="${secretsDir}/wireproxy/${name}"
            conf="${configDir}/${name}.conf"

            # sops-nix decrypts via a launchd agent — wait for it.
            timeout=30
            while [ ! -f "$secret" ] && [ "$timeout" -gt 0 ]; do
              sleep 1
              timeout=$((timeout - 1))
            done
            if [ ! -f "$secret" ]; then
              echo "wireproxy-${name}: timed out waiting for sops secret" >&2
              exit 1
            fi

            mkdir -p "${configDir}"
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
            chmod 600 "$conf"

            exec ${pkgs.wireproxy}/bin/wireproxy -c "$conf"
          '';
      in
      {
        home.packages = [ pkgs.wireproxy ];

        # PAC files for Firefox profiles that need Tailscale access.
        # Routes Tailscale/local traffic directly; everything else through
        # the profile's Mullvad SOCKS5 proxy.
        xdg.configFile = lib.genAttrs
          [ "firefox-pac/personal.pac" "firefox-pac/academic.pac" ]
          (path:
            let
              name = lib.removeSuffix ".pac" (lib.removePrefix "firefox-pac/" path);
              port = toString tunnels.${name}.port;
            in
            {
              text = ''
                // PAC file for the "${name}" Firefox profile.
                // Routes Tailscale traffic directly; everything else through Mullvad SOCKS5.

                function FindProxyForURL(url, host) {
                    // Tailscale IPs (100.64.0.0/10)
                    if (isInNet(host, "100.64.0.0", "255.192.0.0")) {
                        return "DIRECT";
                    }

                    // Tailscale MagicDNS
                    if (shExpMatch(host, "*.ts.net")) {
                        return "DIRECT";
                    }

                    // Localhost and private networks
                    if (isPlainHostName(host) ||
                        host === "localhost" ||
                        host === "127.0.0.1" ||
                        isInNet(host, "10.0.0.0", "255.0.0.0") ||
                        isInNet(host, "172.16.0.0", "255.240.0.0") ||
                        isInNet(host, "192.168.0.0", "255.255.0.0")) {
                        return "DIRECT";
                    }

                    // Everything else through Mullvad
                    return "SOCKS5 127.0.0.1:${port}";
                }
              '';
            });

        # sops secrets — one WireGuard private key per tunnel.
        sops.secrets = lib.mapAttrs' (name: _: lib.nameValuePair "wireproxy/${name}" { }) tunnels;

        # launchd agents — one per tunnel, auto-starts on login.
        # Each agent runs a wrapper that waits for sops decryption, generates
        # the config with the private key, then execs wireproxy.
        launchd.agents = lib.mapAttrs' (
          name: tunnel:
          lib.nameValuePair "wireproxy-${name}" {
            enable = true;
            config = {
              Program = "${mkLauncher name tunnel}";
              KeepAlive = true;
              RunAtLoad = true;
              StandardOutPath = "${configDir}/logs/${name}.log";
              StandardErrorPath = "${configDir}/logs/${name}.err";
            };
          }
        ) tunnels;
      }
    )
  ];
}
