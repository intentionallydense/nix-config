# Nginx reverse proxy for all server services.
# Each service gets a subdomain: jellyfin.carbon, sonarr.carbon, etc.
# Accessible over Tailscale MagicDNS (no TLS needed — Tailscale handles encryption).
# Used by: carbon.
{ ... }:
{
  services.nginx = {
    enable = true;

    # Sensible defaults
    recommendedProxySettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts = {
      "jellyfin.carbon" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:8096";
          proxyWebsockets = true; # Jellyfin uses websockets for live updates
        };
      };

      "sonarr.carbon" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:8989";
        };
      };

      "radarr.carbon" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:7878";
        };
      };

      "lidarr.carbon" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:8686";
        };
      };

      "prowlarr.carbon" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:9696";
        };
      };

      "grafana.carbon" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:3000";
          proxyWebsockets = true; # Grafana live uses websockets
        };
      };
    };
  };

  # Nginx needs port 80
  networking.firewall.allowedTCPPorts = [ 80 ];
}
