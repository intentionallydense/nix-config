# tin — Hetzner Cloud VPS (x86_64-linux, NixOS), Sylvia's home-server-in-the-cloud.
# Single-host flake. The old three-host fleet (carbon/silicon/germanium) lives at
# the `fleet-final` tag; germanium was de-nixed 2026-07-04 (docs referenced there).
{
  description = "NixOS configuration for tin (Hetzner VPS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      sops-nix,
      ...
    }@inputs:
    let
      inherit (self) outputs;

      tinSettings = {
        username = "iodide";
        hostname = "tin";
        # Libraries live outside /home: no ProtectHome punch-through, no
        # ACL-traversal hack, $HOME stays 0700. Moved 2026-06-12.
        musicLibraryDir = "/srv/media/music";
        bookLibraryDir = "/srv/media/books";
      };
    in
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;

      nixosConfigurations.tin = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          sops-nix.nixosModules.sops
          inputs.disko.nixosModules.disko
          ./configuration.nix
        ];
        specialArgs = {
          inherit self inputs outputs;
        } // tinSettings;
      };
    };
}
