# nix-darwin configuration for "germanium" (aarch64-darwin, period 4).
# Mirrors silicon as closely as possible — same shell, packages, and defaults.
# Germanium-specific: claude-wrapper, Tailscale, Touch ID, Cachix substituters.
# Used by: flake.nix darwinConfigurations.germanium
{
  pkgs,
  username,
  hostname,
  ...
}:
{
  imports = [
    ../../modules/home # Shared home-manager modules (starship, tmux, zsh, etc.)
    ../../modules/darwin/aerospace
    ../../modules/darwin/karabiner
    ../../modules/darwin/sketchybar
  ];

  # --- Primary user ---
  system.primaryUser = username;

  # --- Nix ---
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      username
    ];
    # Cachix substituters shared with NixOS host
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org/"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    warn-dirty = false;
    keep-outputs = true;
    keep-derivations = true;
  };

  # --- Networking ---
  networking.hostName = hostname;
  networking.localHostName = hostname;
  networking.computerName = "krypton"; # Period 4 noble gas

  # --- Users ---
  users.users.${username} = {
    home = "/Users/${username}";
    shell = pkgs.fish;
  };

  # --- System packages (mirrors silicon) ---
  environment.systemPackages = with pkgs; [
    coreutils
    curl
    wget
    vim
    git
    gnupg
    jq
    tree

    # Secrets
    sops
    age
    ssh-to-age

    # Nix tooling
    nixfmt
    nil # Nix language server
  ];

  # --- Homebrew (mirrors silicon, minus virtualbox — no ARM support) ---
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    taps = [
      "nikitabobko/tap" # AeroSpace tiling WM
    ];
    brews = [
      "choose-gui" # Fuzzy picker for app launcher script
    ];
    casks = [
      # Browsers
      "firefox"
      "google-chrome"
      "tor-browser"

      # Terminal
      "ghostty"

      # Window management
      "aerospace"
      "karabiner-elements"

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
      # No virtualbox — no ARM support

      # File sharing
      "freetube"

      # Gaming
      "steam"

      # Crypto wallets
      "electrum"
    ];
  };

  # --- macOS system defaults (mirrors silicon) ---
  system.defaults = {
    dock = {
      autohide = true;
      tilesize = 63;
      mru-spaces = false;
      show-recents = false;
    };

    NSGlobalDomain = {
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      "com.apple.swipescrolldirection" = false; # Disable natural scrolling
      AppleShowAllExtensions = true;
      NSAutomaticWindowAnimationsEnabled = false; # Reduces jank with AeroSpace
    };

    finder = {
      AppleShowAllFiles = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "clmv";
    };

    trackpad = {
      Clicking = true; # Tap to click (laptop preference)
      TrackpadRightClick = true;
    };

    CustomUserPreferences = {
      "com.apple.WindowManager" = {
        EnableStandardClickToShowDesktop = false;
      };
    };
  };

  # --- Services ---
  services.tailscale.enable = true;

  # --- Security ---
  security.pam.services.sudo_local.touchIdAuth = true;

  # --- Claude wrapper via launchd ---
  # Mirror of the systemd service on carbon.
  launchd.user.agents.claude-wrapper =
    let
      python = pkgs.python313.withPackages (
        ps: with ps; [
          anthropic
          fastapi
          uvicorn
          python-dotenv
          pydantic
          websockets
          feedparser
          python-multipart
          pymupdf
          setuptools
        ]
      );
    in
    {
      serviceConfig = {
        ProgramArguments = [
          "${python}/bin/python"
          "-m"
          "claude_wrapper.server"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        WorkingDirectory = "/Users/${username}/claude-wrapper/claudepilled";
        EnvironmentVariables = {
          PYTHONPATH = "/Users/${username}/claude-wrapper/claudepilled";
        };
        StandardOutPath = "/tmp/claude-wrapper.log";
        StandardErrorPath = "/tmp/claude-wrapper.err";
      };
    };

  # --- Shell ---
  programs.fish.enable = true;

  # --- Fonts ---
  fonts.packages = with pkgs.nerd-fonts; [
    jetbrains-mono
    fira-code
  ];

  # --- nixpkgs ---
  nixpkgs.config.allowUnfree = true;

  # --- Platform ---
  system.stateVersion = 5;
}
