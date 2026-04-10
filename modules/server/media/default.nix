# Media server stack: Jellyfin + *arr suite + Immich.
# Jellyfin streams video, Sonarr/Radarr automate TV/movie downloads,
# Prowlarr manages indexers for both, Immich manages photos.
# Music is handled separately by modules/server/music/.
# Used by: carbon.
{ pkgs, username, ... }:
{
  # Jellyfin — media streaming server (movies, TV, music)
  services.jellyfin = {
    enable = true;
    openFirewall = true; # Opens 8096 (HTTP) and 8920 (HTTPS)
  };

  # Intel QuickSync hardware transcoding + shared media group
  # Jellyfin needs render/video for hw transcode, plus media group for shared dirs
  users.users.jellyfin.extraGroups = [ "render" "video" "media" ];

  # Sonarr — TV show automation (monitor, search, download, organise)
  services.sonarr = {
    enable = true;
    openFirewall = true; # 8989
  };

  # Radarr — movie automation (same idea as Sonarr but for films)
  services.radarr = {
    enable = true;
    openFirewall = true; # 7878
  };

  # Lidarr removed — music is handled by Navidrome + slskd + beets
  # in modules/server/music/. See that module for the full music pipeline.

  # Prowlarr — indexer manager, feeds search results to Sonarr/Radarr
  services.prowlarr = {
    enable = true;
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

  # Shared media group — all *arr services and the user need access to the same dirs
  users.groups.media = { };
  users.users.${username}.extraGroups = [ "media" ];
  users.users.sonarr.extraGroups = [ "media" ];
  users.users.radarr.extraGroups = [ "media" ];
}
