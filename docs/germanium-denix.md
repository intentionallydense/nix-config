# germanium de-nix — 2026-07-04

germanium (M4 Pro 14", aarch64-darwin) left the nix fleet: nix-darwin,
home-manager, and Determinate Nix all removed. It's plain macOS + Homebrew now.
Motivation: the declarative layer fought macOS more than it helped on this
machine (activation friction, Keyboard Setup Assistant popups on rebuild,
brew/nix-darwin version skew). The other hosts (carbon, tin, silicon) stay NixOS.

Last building config: `bd57ba1` (final pre-denix snapshot). To re-nix, start there.

## Where everything went

| Was (nix) | Is now |
|---|---|
| home-manager dotfiles (~35 store symlinks) | Plain files in place (`~/.config/...`), untracked by choice |
| `config.fish` (generated) | Hand-maintained `~/.config/fish/config.fish`; `fnew`/`finit`/`cgen` + nix templates dropped; `nrs`/`rebuild` aliases dropped |
| fish (login shell) | brew fish, `/opt/homebrew/bin/fish` (in `/etc/shells`, set via chsh) |
| CLI tools (systemPackages + home.packages) | brew: bat btop coreutils direnv eza fd fzf git git-delta gnupg htop jq lazygit nixfmt ripgrep shellcheck sops age starship tealdeer tmux tmuxp trash-cli tree vim wget yazi fish |
| GNU coreutils (unprefixed) | brew coreutils gnubin on PATH (parity preserved) |
| trash-cli (keg-only) | `/opt/homebrew/opt/trash-cli/bin` on PATH |
| wireproxy (no brew formula) | nix-built binary rescued to `~/.local/bin/wireproxy` (links system libs only). Upgrades: github.com/pufferffish/wireproxy releases |
| ssh-to-age (no brew formula) | same rescue → `~/.local/bin/ssh-to-age` |
| wireproxy launchd agents (sops-decrypted at start) | `com.sylvia.wireproxy-{personal,sensitive,academic,social}` plists → static configs at `~/.config/wireproxy/*.conf` (keys embedded, 600). sops-nix agent retired |
| tmux plugins (catppuccin 2023-01-06 / sensible / vim-tmux-navigator) | vendored at `~/.config/tmux/plugins/` — catppuccin is old-syntax; don't "upgrade" it casually |
| lazygit config (generated from catppuccin theme) | reconstructed at `~/Library/Application Support/lazygit/config.yml` (mocha/blue @ d3c95a67) |
| nerd fonts (fonts.packages) | brew casks: font-jetbrains-mono-nerd-font, font-fira-code-nerd-font |
| karabiner.json (force-deployed each rebuild) | already a plain file (Karabiner had overwritten the symlink); ANSI `keyboard_type_v2` pin lives inside it. No rebuilds → no Keyboard Setup Assistant popup, ever |
| aerospace.toml + scripts | plain files; dead `cmd-shift-u` (darwin-rebuild) binding removed — free binding |
| hammerspoon init.lua | plain file |
| Homebrew declarations (taps/brews/casks/masApps) | brew is self-managing now; apps were real installs all along |
| macOS `system.defaults` | already written to plists; re-apply script below if ever needed |
| Touch ID sudo (`security.pam`) | `/etc/pam.d/sudo_local`: `auth sufficient pam_tid.so` (survives OS updates) |
| nix-gc LaunchDaemon | gone with nix |
| kimi-claude-proxy launchd agent (orphan, port 8787) | retired 2026-07-04 (dead experiment, no repo references) |

## Fleet implications

- **Rebuilds**: germanium no longer evals/builds nix. Fleet path is remote:
  `ssh root@100.65.236.26 'nixos-rebuild switch --flake github:intentionallydense/nix-config#tin'`
  (carbon/silicon: ssh in, rebuild from their local checkouts).
- **sops**: the admin key (`~/.config/sops/age/keys.txt`, `age16t99…`) is
  nix-independent; brew sops/age keep secret editing working from germanium
  (verified post-teardown). germanium's *runtime* decryption is gone — the only
  Mac-side runtime consumer of `wireproxy/*` is now silicon. This simplifies
  `docs/sops-key-migration.md`: germanium = editing-only (its own key
  `age15zk95…` is no longer needed for anything).
- This repo's checkout on germanium (`~/nix-config`) remains the fleet admin
  workspace — edits + push from here; hosts pull and rebuild themselves.

## macOS defaults snapshot (re-apply if ever needed)

```sh
# dock
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock tilesize -int 63
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0
# global
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain AppleInterfaceStyle -string Dark
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
# finder
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder FXPreferredViewStyle -string clmv
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder _FXSortFoldersFirst -bool true
# trackpad
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool false
defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
# window manager
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
killall Dock Finder
```
