# nix-config

Unified Nix flake managing three hosts across macOS and NixOS.

| Host | System | Platform | User |
|------|--------|----------|------|
| silicon | x86_64-darwin | Intel Mac | chloride |
| germanium | aarch64-darwin | Apple Silicon Mac | bromide |
| carbon | x86_64-linux | NixOS server | fluoride |

Naming follows the periodic table: hosts are group 14, usernames are group 17
halides, SSH aliases are group 15 pnictogens.

## Structure

```
flake.nix              Entry point
hosts/                 Per-host config (silicon, germanium, carbon)
home/                  macOS-only home-manager (fish extensions, sops, ssh)
modules/
  home/                Shared home-manager modules (fish, git, tmux, ghostty, cli tools, ...)
  darwin/              macOS-only (aerospace, karabiner, sketchybar)
  desktop/             NixOS desktop environments (Hyprland, i3, GNOME)
  hardware/            NixOS hardware (GPU, drives)
  programs/            NixOS programs (browsers, editors, media)
  scripts/             Shell scripts
  themes/              GTK/QT theming (Catppuccin)
overlays/              Custom overlays
pkgs/                  Custom derivations
secrets/               sops-encrypted secrets
```

## Usage

**macOS (nix-darwin):**
```sh
darwin-rebuild switch --flake .#silicon    # Intel Mac
darwin-rebuild switch --flake .#germanium  # Apple Silicon
```

**NixOS:**
```sh
sudo nixos-rebuild switch --flake .#carbon
```

## Key details

- **Fish** is the default shell on all hosts
- **Ghostty** is the terminal everywhere (homebrew cask on macOS, nixpkgs on NixOS)
- **Catppuccin Mocha** theming throughout (Ghostty, tmux, btop, lazygit, GTK/QT)
- **AeroSpace** tiling WM on macOS with SketchyBar workspace indicators
- **Hyprland** on NixOS
- Shared modules in `modules/home/` use `home-manager.sharedModules` so they work
  identically on both nix-darwin and NixOS
- Secrets managed with [sops-nix](https://github.com/Mic92/sops-nix), encrypted
  with an age key derived from the SSH ed25519 key

## Keybindings

AeroSpace has a built-in cheatsheet: `cmd-shift-i`. The source is at
`modules/darwin/aerospace/scripts/keybinds.sh`.

Tmux uses `ctrl-a` as prefix. Hyprland uses `Super` as the main modifier.
All three use vim-style `hjkl` navigation.

## Credits

NixOS desktop config forked from [Sly-Harvey/NixOS](https://github.com/Sly-Harvey/NixOS).
