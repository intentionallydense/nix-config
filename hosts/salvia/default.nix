# System-level nix-darwin configuration for the "salvia" host.
# Manages: nix settings, system packages, homebrew casks, macOS defaults.
# Used by: flake.nix as the main darwin module.
{
  pkgs,
  username,
  hostname,
  ...
}:

{
  # --- Primary user (required by nix-darwin for user-specific options) ---
  system.primaryUser = username;

  # --- Nix ---
  # Using the official Nix installer (Determinate doesn't support x86_64-darwin).
  # nix-darwin manages nix.conf and the daemon.
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      username
    ];
  };

  # --- Networking ---
  networking.hostName = hostname;
  networking.localHostName = "salvia";

  # --- Users ---
  users.users.${username} = {
    home = "/Users/${username}";
    shell = pkgs.fish;
  };

  # --- System packages (CLI tools available system-wide) ---
  environment.systemPackages = with pkgs; [
    coreutils
    curl
    wget
    vim
    gnupg
    tree

    # Secrets
    sops
    age
    ssh-to-age

    # Nix tooling
    nixfmt
    nil # Nix language server
  ];

  # --- Homebrew (GUI casks only) ---
  # Homebrew must be installed before first `darwin-rebuild switch`.
  # nix-darwin calls `brew bundle` to install/manage these casks.
  homebrew = {
    enable = true;
    onActivation = {
      # "none" is safe while building up the list. Switch to "zap" once
      # you're confident the list is complete — it removes unlisted casks.
      cleanup = "none";
      autoUpdate = true;
      upgrade = true;
    };
    casks = [
      # Browsers
      "firefox"
      "google-chrome"
      "tor-browser"

      # Terminal
      "ghostty"

      # Communication
      "signal"
      "slack"
      "whatsapp"
      "zoom"

      # Productivity
      "obsidian"
      "zotero"

      # Media
      "spotify"
      "vlc"
      "krita"
      "musicbrainz-picard"
      "anki"
      "foobar2000"

      # Development
      "pycharm-ce"
      "rustrover"

      # Utilities
      "linearmouse"
      "mullvad-vpn"
      "tailscale"
      "selfcontrol"
      "balenaetcher"
      "ollama"
      "utm"
      "virtualbox"

      # File sharing
      "qbittorrent"
      "freetube"

      # Gaming
      "steam"

      # Crypto wallets
      "electrum"
    ];
  };

  # --- macOS system defaults ---
  # Captured from current system on 2026-03-27.
  system.defaults = {
    dock = {
      autohide = true;
      tilesize = 63;
      show-recents = false;
    };

    NSGlobalDomain = {
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      "com.apple.swipescrolldirection" = false; # Disable natural scrolling
      AppleShowAllExtensions = true;
    };

    finder = {
      AppleShowAllFiles = true;
      FXEnableExtensionChangeWarning = false;
    };

    trackpad = {
      Clicking = false; # No tap-to-click
      TrackpadRightClick = true;
    };
  };

  # --- Shell ---
  programs.zsh.enable = true; # Keep for compatibility during fish migration
  programs.fish.enable = true; # Primary shell

  # --- Platform ---
  system.stateVersion = 5;
}
