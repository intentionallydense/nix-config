# Media server stack: Jellyfin + *arr suite + Immich.
# Jellyfin streams video, Sonarr/Radarr automate TV/movie downloads,
# Prowlarr manages indexers for both, Immich manages photos.
# Music is handled separately by modules/server/music/.
# Used by: carbon.
{ pkgs, lib, config, username, ... }:
{
  # Jellyfin — media streaming server (movies, TV, music)
  services.jellyfin = {
    enable = true;
    openFirewall = true; # Opens 8096 (HTTP) and 8920 (HTTPS)
  };

  # Intel QuickSync hardware transcoding + shared media group
  # Jellyfin needs render/video for hw transcode, plus media group for shared dirs
  users.users.jellyfin.extraGroups = [ "render" "video" "media" ];

  # Sonarr / Radarr / Prowlarr — disabled 2026-04-24 to claw back
  # ~300MB during memory pressure from the Immich dedup job on a 16GB box.
  # Re-enable (flip to `enable = true`) when actively adding shows/movies.
  services.sonarr = {
    enable = false;
    openFirewall = true; # 8989
  };

  services.radarr = {
    enable = false;
    openFirewall = true; # 7878
  };

  # Lidarr removed — music is handled by Navidrome + slskd + beets
  # in modules/server/music/. See that module for the full music pipeline.

  # Indexer manager — only useful while sonarr/radarr are active.
  services.prowlarr = {
    enable = false;
    openFirewall = true; # 9696
  };

  # Immich — self-hosted Google Photos (photo backup, search, sharing)
  # Runs on port 2283
  services.immich = {
    enable = true;
    openFirewall = true;
    host = "0.0.0.0"; # Listen on all interfaces (access gated by Tailscale firewall)
    machine-learning.enable = true; # Smart search, face recognition, object detection
  };

  # qBittorrent — torrent client with web UI, used by Sonarr/Radarr/Lidarr
  # Disabled while on eduroam. Uncomment when on a different network.
  # services.qbittorrent = {
  #   enable = true;
  #   openFirewall = true; # Opens 8080 (web UI) and 6881 (BT traffic)
  #   serverConfig = {
  #     LegalNotice.Accepted = true;
  #     Preferences = {
  #       "WebUI\\Address" = "0.0.0.0";
  #     };
  #   };
  # };

  # Shared media group — users only added when the corresponding service
  # is enabled (the service module creates the user). Keeps disabled
  # services from triggering "user missing group/isSystemUser" assertions.
  users.groups.media = { };
  users.users.${username}.extraGroups = [ "media" ];
  users.users.sonarr = lib.mkIf config.services.sonarr.enable {
    extraGroups = [ "media" ];
  };
  users.users.radarr = lib.mkIf config.services.radarr.enable {
    extraGroups = [ "media" ];
  };
}
