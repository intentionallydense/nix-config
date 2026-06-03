# nix-darwin configuration for "germanium" (aarch64-darwin, period 4).
# Mirrors silicon as closely as possible — same shell, packages, and defaults.
# Germanium-specific: Tailscale, Touch ID, Cachix substituters.
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
    ../../modules/darwin/wireproxy # Mullvad WireGuard SOCKS5 proxies for Firefox profiles
  ];

  # --- Primary user ---
  system.primaryUser = username;

  # --- Nix ---
  # Determinate Nix manages the daemon itself; nix-darwin must not touch it.
  nix.enable = false;
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
      "athevon/tokeneater" # TokenEater menu-bar Claude usage monitor
    ];
    brews = [
      "choose-gui" # Fuzzy picker for app launcher script
      "mas" # Mac App Store CLI (drives masApps below)
    ];
    casks = [
      # Browsers
      "firefox"

      # Terminal
      "ghostty"

      # Window management
      "aerospace"
      "karabiner-elements"

      # Communication
      "beeper"
      "signal"
      "slack"
      "whatsapp"

      # Productivity
      "obsidian"
      "zotero"
      "claude" # Claude desktop app (adopted into brew on 2026-06-03)

      # Media
      "vlc"
      "musicbrainz-picard"
      "anki"

      # Utilities
      "linearmouse"
      "mullvad-vpn"
      "tailscale"
      "selfcontrol"
      "ollama"
      "tokeneater" # Menu-bar Claude usage monitor
      "utm"
      # No virtualbox — no ARM support

      # Video
      "yattee"

      # Gaming
      "steam"

      # Crypto wallets
      "electrum"
    ];

    # Mac App Store apps (requires being signed in to the App Store)
    masApps = {
      Amphetamine = 937984704; # verified against `mas list` on 2026-06-03
    };
  };

  # --- macOS system defaults (mirrors silicon) ---
  system.defaults = {
    dock = {
      autohide = true;
      tilesize = 63;
      mru-spaces = false;
      show-recents = false;
      autohide-delay = 0.0; # No delay before the dock slides in
      autohide-time-modifier = 0.0; # Instant show/hide animation
    };

    NSGlobalDomain = {
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      "com.apple.swipescrolldirection" = false; # Disable natural scrolling
      AppleShowAllExtensions = true;
      NSAutomaticWindowAnimationsEnabled = false; # Reduces jank with AeroSpace
      ApplePressAndHoldEnabled = false; # Hold = key-repeat, not the accent popover (vim)
      AppleInterfaceStyle = "Dark"; # Pin dark mode
      # Stop macOS "fixing" code/prose as you type
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
    };

    finder = {
      AppleShowAllFiles = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "clmv";
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXSortFoldersFirst = true;
    };

    trackpad = {
      Clicking = true; # Tap to click (laptop preference)
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true; # Three-finger drag to move windows
    };

    CustomUserPreferences = {
      "com.apple.WindowManager" = {
        EnableStandardClickToShowDesktop = false;
      };
    };
  };

  # --- Services ---
  services.tailscale.enable = true;

  # --- Garbage collection ---
  # Determinate Nix owns the daemon (nix.enable = false above), so nix-darwin's
  # built-in nix.gc is inert. Run nix-collect-garbage weekly as a standalone
  # root LaunchDaemon instead. Trims old system generations + frees the store.
  launchd.daemons.nix-gc = {
    serviceConfig = {
      ProgramArguments = [
        "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
        "--delete-older-than"
        "30d"
      ];
      StartCalendarInterval = [
        {
          Weekday = 0; # Sunday
          Hour = 3;
          Minute = 15;
        }
      ];
      StandardOutPath = "/tmp/nix-gc.log";
      StandardErrorPath = "/tmp/nix-gc.err";
      RunAtLoad = false;
    };
  };

  # --- Security ---
  security.pam.services.sudo_local.touchIdAuth = true;

  # --- Shell ---
  programs.fish.enable = true;
  # Make fish a permissible login shell so `chsh` accepts it. nix-darwin maps
  # this to the stable /run/current-system/sw/bin/fish path (survives fish
  # upgrades + GC), not a raw store path.
  environment.shells = [ pkgs.fish ];

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
