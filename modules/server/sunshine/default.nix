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

  # Grant input group access to uinput so Sunshine can create virtual input devices
  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", GROUP="input", MODE="0660"
  '';
}
