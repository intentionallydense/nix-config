# Architecture

Unified flake managing three hosts: macOS "silicon" (x86_64-darwin), macOS "germanium"
(aarch64-darwin), and NixOS server "carbon" (x86_64-linux). All share a single nixpkgs
input and a set of portable home-manager modules.

Naming scheme: hosts are group 14 elements, usernames are group 17 halides, SSH aliases
are group 15 pnictogens, computer names are group 18 noble gases.

## File map

```
flake.nix                             Entry point: inputs, darwinConfigurations, nixosConfigurations

hosts/
  silicon/default.nix                 macOS Intel (chloride): nix settings, brew casks, macOS defaults
  germanium/configuration.nix         macOS Apple Silicon (bromide): brew casks, macOS defaults, claude-wrapper
  carbon/configuration.nix            NixOS (fluoride): imports all server modules (Hyprland, hardware, etc.)
  carbon/hardware-configuration.nix   Auto-generated hardware config for the NixOS server
  common.nix                          Shared NixOS config: users, boot, audio, fonts, nix settings

home/
  default.nix                         macOS-only home-manager (fish extensions, sops, ssh, direnv stable override)

modules/
  home/                               ** Shared home-manager modules — portable to NixOS + darwin **
    default.nix                       Imports all sub-modules below
    cli/                              Common CLI tools (bat, eza, fzf, htop, jq, ripgrep)
    fish/                             Fish shell (greeting, platform-aware aliases)
    git/                              Git (identity, SSH signing, delta pager)
    ghostty/                          Ghostty terminal (Catppuccin Mocha, installs on Linux, config on both)
    starship/                         Shell prompt
    tmux/                             Terminal multiplexer
    direnv/                           Per-project env (+ nix-direnv)
    lazygit/                          Git TUI with catppuccin theme
    btop/                             System monitor with catppuccin theme
    yazi/                             Terminal file manager
    cava/                             Audio visualizer (entire module gated behind isLinux)

  darwin/                             ** macOS-only modules **
    aerospace/                        Tiling WM config, app launcher, project picker, session switcher, scratchpad
    karabiner/                        Caps→Escape/Hyper key mapping
    sketchybar/                       Menu bar with AeroSpace workspace indicators

  desktop/                            NixOS desktop environments (Hyprland, i3, GNOME)
  hardware/                           NixOS hardware (GPU drivers, drive mounts)
  programs/                           NixOS program modules (browsers, editors, media, misc)
  scripts/                            NixOS shell scripts (screenshot, rebuild, etc.)
  themes/                             GTK/QT themes (Catppuccin)

overlays/default.nix                  Custom overlays (NUR, stable nixpkgs, custom packages)
pkgs/                                 Custom derivations (SDDM themes, etc.)
secrets/                              sops-encrypted secrets (silicon)
.sops.yaml                            sops key configuration
```

## Key decisions

- **modules/home/ is the shared layer**: All pure home-manager modules (starship, tmux,
  fish, git, ghostty, cli tools, etc.) live here and are imported by both darwin and
  NixOS hosts. NixOS-only features (fonts.packages, ALSA-dependent programs, Linux-specific
  aliases) are gated behind `lib.mkIf pkgs.stdenv.isLinux`.
- **home-manager.sharedModules pattern**: Shared modules use `home-manager.sharedModules`
  rather than being pure HM modules. This lets them set system-level options alongside
  HM config and works identically in both NixOS and nix-darwin contexts.
- **Fish is the only shell on all hosts**: Both macOS and NixOS use fish as the default
  interactive shell. Tmux also defaults to fish.
- **Ghostty is the terminal on all hosts**: Catppuccin Mocha themed, no window decorations.
  Installed via homebrew cask on macOS, via nixpkgs on NixOS. macOS-specific settings
  (option-as-alt, keybind overrides) are gated behind isDarwin.
- **Git identity is shared**: Same user/email/signing config across all hosts via
  modules/home/git. SSH key signing with ed25519.
- **CLI tools as programs.* not packages**: bat, eza, fzf, htop, jq, ripgrep are configured
  via home-manager programs.* for proper shell integration, not just installed as packages.
- **Aerospace keybinds**: cmd-shift is the system modifier (AeroSpace), alt is reserved
  for app-level bindings (Ghostty, tmux). Vim keys for focus/move, resize mode, workspaces
  1-10. App launcher letters aligned with Hyprland (T=terminal, E=files, etc.).
- **Aerospace requires nikitabobko/tap**: Not in the default homebrew cask repo. Both
  silicon and germanium declare this tap in their homebrew config.
- **App launcher**: choose-gui (open-source dmenu clone) piped through a shell script,
  triggered by cmd-shift-space. AeroSpace floats the choose window.
- **SketchyBar**: Launched by AeroSpace on startup, notified on workspace change via
  `exec-on-workspace-change`. Catppuccin Mocha themed.
- **Karabiner**: Caps Lock → Escape (tap) / Hyper (Cmd+Ctrl+Opt+Shift, hold).
  Deployed declaratively via home.file with force=true since Karabiner rewrites its config.
  Activation hook kills the GUI to prevent it popping up on rebuild.
- **Activation hooks**: AeroSpace relaunches on rebuild (picks up config changes).
  Karabiner GUI gets killed on rebuild (prevents popup). Both via home.activation.
- **Both Macs share home/default.nix**: macOS-specific fish extensions (conda, ghcup, etc.),
  SSH match blocks, direnv stable override, sops. Portable programs moved to modules/home/.
- **Three hosts coexist**: silicon (Intel Mac, fish), germanium (ARM Mac, fish),
  carbon (NixOS, Hyprland, fish). All import modules/home/; Macs also import home/default.nix.

## Data flow

```
flake.nix
  ├── darwinConfigurations.silicon
  │     ├── hosts/silicon/default.nix
  │     ├── modules/home/*            (shared: fish, git, ghostty, cli, tmux, etc.)
  │     ├── modules/darwin/aerospace  (tiling WM + app launcher)
  │     ├── modules/darwin/karabiner  (key remapping)
  │     ├── modules/darwin/sketchybar (workspace bar)
  │     └── home/default.nix (macOS fish extensions, sops, ssh, direnv override)
  ├── darwinConfigurations.germanium
  │     ├── hosts/germanium/configuration.nix
  │     ├── modules/home/*            (shared: fish, git, ghostty, cli, tmux, etc.)
  │     ├── modules/darwin/aerospace  (tiling WM + app launcher)
  │     ├── modules/darwin/karabiner  (key remapping)
  │     ├── modules/darwin/sketchybar (workspace bar)
  │     └── home/default.nix (macOS fish extensions, sops, ssh, direnv override)
  └── nixosConfigurations.carbon
        ├── hosts/carbon/configuration.nix → hosts/common.nix
        ├── modules/home/*           (shared: fish, git, ghostty, cli, tmux, etc.)
        └── modules/{desktop,hardware,programs}/* (NixOS-only)
```
