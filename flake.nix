# Unified nix config — NixOS fleet: carbon + tin (x86_64-linux), silicon
# (x86_64-linux, real config on the silicon-nixos branch; the darwin entry here
# is dead legacy pending the branch fold-in).
# germanium (macOS) was de-nixed 2026-07-04 — see docs/germanium-denix.md.
{
  description = "nix-darwin + NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- NixOS server (carbon) inputs ---
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:Sly-Harvey/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neovim = {
      url = "github:Sly-Harvey/nvim";
      flake = false;
    };
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur.url = "github:nix-community/NUR";
    betterfox = {
      url = "github:yokoffing/Betterfox";
      flake = false;
    };
    thunderbird-catppuccin = {
      url = "github:catppuccin/thunderbird";
      flake = false;
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvchad4nix = {
      url = "github:nix-community/nix4nvchad";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      nix-darwin,
      home-manager,
      sops-nix,
      ...
    }@inputs:
    let
      inherit (self) outputs;

      # --- macOS (silicon) — Intel Mac, period 3 ---
      siliconSystem = "x86_64-darwin";
      siliconHostname = "silicon";
      siliconUsername = "chloride";

      # germanium (M4 Pro, aarch64-darwin) was de-nixed 2026-07-04 — plain macOS
      # + Homebrew now. See docs/germanium-denix.md for where everything went.

      # --- NixOS (carbon) ---
      carbonSettings = {
        username = "fluoride";
        editor = "nixvim";
        browser = "firefox";
        terminal = "ghostty";
        terminalFileManager = "yazi";
        sddmTheme = "purple_leaves";
        wallpaper = "kurzgesagt";
        videoDriver = "intel";
        hostname = "carbon";
        locale = "en_GB.UTF-8";
        timezone = "Europe/London";
        kbdLayout = "gb";
        kbdVariant = "extd";
        consoleKeymap = "uk";
        vaultName = "magnesium";
        # Library roots for modules/server/{music,books} — carbon's libraries
        # predate the parameterization and live in $HOME (with the 0710 +
        # named-user-ACL traversal scheme).
        musicLibraryDir = "/home/fluoride/music_library";
        bookLibraryDir = "/home/fluoride/book_library";
      };

      # --- NixOS (tin) — Hetzner Cloud VPS (x86_64), period 5 ---
      tinSettings = {
        username = "iodide";
        hostname = "tin";
        # Libraries live outside /home: no ProtectHome punch-through, no
        # ACL-traversal hack, $HOME stays 0700. Moved 2026-06-12.
        musicLibraryDir = "/srv/media/music";
        bookLibraryDir = "/srv/media/books";
      };

      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      overlays = import ./overlays {
        inherit inputs;
        settings = carbonSettings;
      };

      darwinConfigurations = {
        # --- silicon (Intel Mac, x86_64-darwin) ---
        ${siliconHostname} = nix-darwin.lib.darwinSystem {
          system = siliconSystem;
          specialArgs = {
            inherit self inputs;
            username = siliconUsername;
            hostname = siliconHostname;
            terminalFileManager = "yazi";
            vaultName = "calcium";
          };
          modules = [
            ./hosts/silicon
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.extraSpecialArgs = {
                pkgs-stable = import nixpkgs-stable {
                  system = siliconSystem;
                  config.allowUnfree = true;
                };
              };
              home-manager.users.${siliconUsername} = {
                imports = [
                  sops-nix.homeManagerModules.sops
                  ./home
                ];
              };
            }
          ];
        };

        # germanium retired 2026-07-04 (de-nixed to plain macOS + Homebrew).
        # Last building config: commit bd57ba1. docs/germanium-denix.md has the map.
      };

      # --- NixOS server ---
      nixosConfigurations.carbon = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/carbon/configuration.nix
        ];
        specialArgs = {
          inherit self inputs outputs;
        } // carbonSettings;
      };

      # --- NixOS server in the cloud (tin, Hetzner VPS, x86_64) ---
      nixosConfigurations.tin = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          sops-nix.nixosModules.sops
          inputs.disko.nixosModules.disko
          ./hosts/tin/configuration.nix
        ];
        specialArgs = {
          inherit self inputs outputs;
        } // tinSettings;
      };
    };
}
