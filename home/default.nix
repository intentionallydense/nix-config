# macOS-specific home-manager configuration (silicon + germanium).
# Manages: mac-specific fish extensions, ssh, direnv (stable pkg override), sops.
# Portable programs (git, bat, eza, fzf, delta, ghostty, etc.) live in modules/home/.
# Used by: flake.nix via home-manager.darwinModules.home-manager.
{ pkgs, pkgs-stable, config, ... }:

{
  home.stateVersion = "24.11";

  # --- User packages ---
  home.packages = with pkgs; [
    fd
    shellcheck
    tldr
  ];

  # --- Environment variables ---
  home.sessionPath = [
    "$HOME/.local/bin" # pipx
    "/usr/local/sbin"
  ];

  # --- Fish (macOS extensions) ---
  # Base fish config (aliases, greeting) is in modules/home/fish.
  # This adds mac-specific interactive init (ghcup, juliaup, opam, antigravity).
  programs.fish.interactiveShellInit = ''
    # ghcup (Haskell) — ghcup env is bash-only, add paths manually
    if test -d "$HOME/.ghcup/bin"
      fish_add_path "$HOME/.ghcup/bin"
      fish_add_path "$HOME/.cabal/bin"
    end

    # juliaup
    fish_add_path "$HOME/.juliaup/bin"

    # opam (OCaml)
    if type -q opam
      eval (opam env --shell=fish 2>/dev/null)
    end

    # conda / mamba / ccm are now in the shared fish module (modules/home/fish).

    # Antigravity
    if test -d "$HOME/.antigravity/antigravity/bin"
      fish_add_path "$HOME/.antigravity/antigravity/bin"
    end
  '';

  # --- SSH ---
  programs.ssh = {
    enable = true;
    # Adopt the new home-manager default (no implicit "*" block). The legacy
    # defaults it used to inject all mirror OpenSSH's own, so effective config
    # is unchanged — this just silences the deprecation warning. 2026-06-02.
    enableDefaultConfig = false;
    matchBlocks = {
      "nitrogen" = {
        # carbon (NixOS server, period 2) — group 15 = nitrogen
        user = "fluoride";
        hostname = "100.124.5.91"; # Tailscale IP (MagicDNS off)
        # Was :2200 (plain sshd for the Colab tunnel) — that's gone, so this now
        # connects over Tailscale SSH on :22 (identity-based auth). 2026-06-01.
      };
      "carbon" = {
        # direct alias for carbon (literal-name convenience over `nitrogen`)
        user = "fluoride";
        hostname = "100.124.5.91";
      };
    };
  };

  # --- Direnv (macOS override) ---
  # Shared direnv config is in modules/home/direnv (includes hide_env_diff).
  # This overrides the package to stable because unstable direnv fails CGO
  # build on x86_64-darwin.
  programs.direnv.package = pkgs-stable.direnv;

  # --- sops-nix ---
  # Secrets are decrypted at activation time using the SSH ed25519 key
  # and the age key imported from silicon.
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  };
}
