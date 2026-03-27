# Unified nix config — macOS (salvia) + NixOS (carbon).
# To migrate salvia to Apple Silicon, change darwinSystem to "aarch64-darwin".
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
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
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

      # --- macOS (salvia) ---
      darwinSystem = "x86_64-darwin"; # Change to "aarch64-darwin" for Apple Silicon
      darwinHostname = "salvia";
      darwinUsername = "anthonyhan";

      # --- NixOS (carbon) ---
      carbonSettings = {
        username = "fluoride";
        editor = "nixvim";
        browser = "firefox";
        terminal = "kitty";
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

      # --- macOS ---
      darwinConfigurations.${darwinHostname} = nix-darwin.lib.darwinSystem {
        system = darwinSystem;
        specialArgs = {
          inherit inputs;
          username = darwinUsername;
          hostname = darwinHostname;
        };
        modules = [
          ./hosts/salvia
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              pkgs-stable = import nixpkgs-stable {
                system = darwinSystem;
                config.allowUnfree = true;
              };
            };
            home-manager.users.${darwinUsername} = {
              imports = [
                sops-nix.homeManagerModules.sops
                ./home
              ];
            };
          }
        ];
      };

      # --- NixOS server ---
      nixosConfigurations.carbon = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/carbon/configuration.nix ];
        specialArgs = {
          inherit self inputs outputs;
        } // carbonSettings;
      };
    };
}
