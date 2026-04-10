# Samba file server — exposes folders as network drives.
# Accessible over Tailscale (trustedInterfaces handles firewall).
# Used by: carbon.
{ username, ... }:
{
  services.samba = {
    enable = true;
    openFirewall = true; # 445 (SMB), 139 (NetBIOS)

    settings = {
      global = {
        "server string" = "carbon";
        "server role" = "standalone";

        # Security: only allow Tailscale and localhost
        "hosts allow" = "100. 127.0.0.1 ::1";
        "hosts deny" = "0.0.0.0/0";

        # No guest access — require authentication
        "map to guest" = "never";

        # macOS compatibility (germanium/silicon)
        "vfs objects" = "fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "MacSamba";
      };

      music = {
        path = "/home/${username}/music_library";
        browseable = "yes";
        "read only" = "no";
        "valid users" = username;
        comment = "Music library";
      };

      projects = {
        path = "/home/${username}/projects";
        browseable = "yes";
        "read only" = "no";
        "valid users" = username;
        comment = "Project folders";
      };
    };
  };
}
