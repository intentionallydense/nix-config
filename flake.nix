# Unified nix config — macOS (silicon, germanium) + NixOS (carbon).
# Three hosts: silicon (x86_64-darwin), germanium (aarch64-darwin), carbon (x86_64-linux).
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

      # --- macOS (silicon) — Intel Mac, period 3 ---
      siliconSystem = "x86_64-darwin";
      siliconHostname = "silicon";
      siliconUsername = "chloride";

      # --- macOS (germanium) — Apple Silicon, period 4 ---
      germaniumSettings = {
        username = "bromide";
        hostname = "germanium";
        editor = "nvim";
        browser = "firefox";
        terminal = "ghostty";
        terminalFileManager = "yazi";
      };

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

        # --- germanium (Apple Silicon, aarch64-darwin, period 4) ---
        germanium = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = {
            inherit self inputs outputs;
          } // germaniumSettings;
          modules = [
            ./hosts/germanium/configuration.nix
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.extraSpecialArgs = {
                pkgs-stable = import nixpkgs-stable {
                  system = "aarch64-darwin";
                  config.allowUnfree = true;
                };
              };
              home-manager.users.${germaniumSettings.username} = {
                imports = [
                  sops-nix.homeManagerModules.sops
                  ./home
                ];
              };
            }
          ];
        };
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
    };
}
