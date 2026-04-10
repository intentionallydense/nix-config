# Remote desktop streaming via Sunshine (Moonlight-compatible).
# Streams the Hyprland Wayland session for remote access from Mac/iOS.
# Used by: carbon. Client: Moonlight on silicon/silly.
{ username, ... }:
{
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true; # needed for KMS/DRM capture on Wayland
    openFirewall = false; # only reachable via Tailscale (trustedInterfaces)
  };

  # Sunshine needs access to input devices for remote keyboard/mouse
  users.users.${username}.extraGroups = [ "input" ];
}
