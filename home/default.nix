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
    matchBlocks = {
      "nitrogen" = {
        # carbon (NixOS server, period 2) — group 15 = nitrogen
        user = "fluoride";
        hostname = "100.124.5.91"; # Tailscale IP (MagicDNS off)
        port = 2200; # regular sshd, bypasses Tailscale SSH
      };
      "carbon" = {
        # direct alias for carbon (used by colab tunnel)
        user = "fluoride";
        hostname = "100.124.5.91";
        port = 2200;
      };
      "colab" = {
        # Colab Pro VM via reverse tunnel through carbon.
        # Host key checking is disabled because Colab VMs are ephemeral —
        # each session gets a new host key, so verification is meaningless.
        hostname = "localhost";
        port = 2222;
        user = "root";
        proxyJump = "carbon";
        extraOptions = {
          StrictHostKeyChecking = "no";
          UserKnownHostsFile = "/dev/null";
        };
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
