# Architecture

Unified flake managing macOS host "salvia" (nix-darwin + home-manager) and NixOS
server "carbon". Both share a single `nixpkgs` input.

## File map

```
flake.nix                         Entry point: all inputs, darwinConfigurations + nixosConfigurations
hosts/
  salvia/default.nix              macOS system config: nix settings, brew casks, macOS defaults
  carbon/configuration.nix        NixOS system config: imports all server modules
  carbon/hardware-configuration.nix  Auto-generated hardware config for the server
  common.nix                      Shared NixOS config: users, boot, audio, fonts, nix settings
home/
  default.nix                     macOS home-manager: fish, zsh, git, ssh, direnv, ghostty, sops
modules/                          NixOS server modules (desktop, hardware, programs, themes, scripts)
overlays/default.nix              Custom overlays (NUR, stable nixpkgs, custom packages)
pkgs/                             Custom derivations (sddm themes, etc.)
secrets/                          sops-encrypted secrets (age-encrypted via SSH key)
.sops.yaml                        sops key configuration
nix-server/                       Original NixOS config archive (reference only)
```

## Key decisions

- **Official Nix installer** (not Determinate): Determinate dropped x86_64-darwin support.
  nix-darwin manages nix.conf and the daemon.
- **Fish as primary shell**: Migrating from zsh. Both are configured — zsh kept for
  compatibility with version managers that don't support fish natively (nvm).
- **Homebrew for GUI casks only**: CLI tools go in nixpkgs. Homebrew is kept solely
  for macOS GUI apps not packaged in nixpkgs.
- **sops-nix via home-manager**: Secrets encrypted with age, derived from the SSH
  ed25519 key. Decrypted at home-manager activation time, not system-level.
- **Ghostty**: Installed via homebrew cask, config managed by home-manager via
  xdg.configFile (avoids nixpkgs build issues on x86_64-darwin).
- **Single `darwinSystem` variable**: Changing `"x86_64-darwin"` to `"aarch64-darwin"`
  in flake.nix is the only change for Apple Silicon migration.
- **Server config preserved**: The NixOS "carbon" config was extracted from the zip
  with its module structure intact. Module import paths (../../modules/...) resolve
  correctly from hosts/carbon/.

## Data flow

```
flake.nix
  ├── darwinConfigurations.salvia
  │     ├── hosts/salvia/default.nix    (system: brew, defaults, nix settings)
  │     └── home/default.nix            (user: fish, git+ssh-signing, direnv, ghostty, sops)
  │           └── sops-nix.homeManagerModules.sops
  └── nixosConfigurations.carbon
        ├── hosts/carbon/configuration.nix → hosts/common.nix
        └── modules/**                     (hyprland, programs, hardware, themes)
```

## Secrets flow

```
~/.ssh/id_ed25519 → ssh-to-age → age key
.sops.yaml defines which age keys can decrypt
sops secrets/secrets.yaml → encrypted at rest
darwin-rebuild switch → home-manager activates → sops decrypts to /run/user/.../secrets
```
