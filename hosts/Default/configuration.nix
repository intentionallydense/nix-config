{
  pkgs,
  videoDriver,
  username,
  hostname,
  browser,
  editor,
  terminal,
  terminalFileManager,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/hardware/video/${videoDriver}.nix # Enable gpu drivers defined in flake.nix
    ../../modules/hardware/drives

    ../common.nix
    ../../modules/scripts

    ../../modules/desktop/hyprland # Enable hyprland window manager
    # ../../modules/desktop/i3-gaps # Enable i3 window manager

    # ../../modules/programs/games
    ../../modules/programs/browser/${browser} # Set browser defined in flake.nix
    ../../modules/programs/terminal/${terminal} # Set terminal defined in flake.nix
    ../../modules/programs/editor/${editor} # Set editor defined in flake.nix
    ../../modules/programs/cli/${terminalFileManager} # Set file-manager defined in flake.nix
    ../../modules/programs/cli/starship
    ../../modules/programs/cli/tmux
    ../../modules/programs/cli/direnv
    ../../modules/programs/cli/lazygit
    ../../modules/programs/cli/cava
    ../../modules/programs/cli/btop
    ../../modules/programs/shell/bash
    ../../modules/programs/shell/zsh
    # ../../modules/programs/media/discord
    # ../../modules/programs/media/spicetify
    # ../../modules/programs/media/youtube-music
    # ../../modules/programs/media/thunderbird
    # ../../modules/programs/media/obs-studio
    # ../../modules/programs/media/mpv
    ../../modules/programs/misc/tlp
    ../../modules/programs/misc/thunar
    ../../modules/programs/misc/lact # GPU fan, clock and power configuration
    ../../modules/programs/misc/nix-ld
    # ../../modules/programs/misc/virt-manager
  ];

  # Home-manager config
  home-manager.sharedModules = [
    (_: {
      home.packages = with pkgs; [
        # obsidian
        # github-desktop
      ];
    })
  ];

  # Define system packages here
  environment.systemPackages = with pkgs; [
    vim
    wget
    waybar
    wofi
    wl-clipboard
    grim slurp
    swaynotificationcenter
    git
    signal-desktop
    jetbrains.rust-rover
    spotify
    jetbrains.pycharm-oss
    mullvad-vpn
    zotero
    # obsidian
    # taskwarrior
    # gcalcli
    python3
    curl
    git
    spawn_fcgi

    # familiar sensors
    ffmpeg        # webcam capture
    sox           # audio (play notification sounds)
    libnotify     # desktop notifications
  ];

  networking.hostName = hostname; # Set hostname defined in flake.nix

  # Stream my media to my devices via the network
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "${username}";
    dataDir = "/home/${username}"; # default location for new folders
    configDir = "/home/${username}/.config/syncthing";
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  networking.nameservers = [ "1.1.1.1" "8.8.8.8" "8.8.4.4" ];

}
