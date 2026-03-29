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
  # This adds mac-specific interactive init (dev toolchains, conda, etc.).
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

    # conda / mamba
    if test -f "$HOME/miniforge3/bin/conda"
      eval "$HOME/miniforge3/bin/conda" "shell.fish" "hook" $argv | source
    end
    if test -f "$HOME/miniforge3/bin/mamba"
      set -gx MAMBA_EXE "$HOME/miniforge3/bin/mamba"
      set -gx MAMBA_ROOT_PREFIX "$HOME/miniforge3"
      "$MAMBA_EXE" shell hook --shell fish --root-prefix "$MAMBA_ROOT_PREFIX" | source
    end

    # ccm — auto-activate conda env when cd'ing into a project with .conda-env
    function _ccm_conda_auto --on-variable PWD
      if test -f .conda-env
        set -l env_name (string trim < .conda-env)
        if test "$CONDA_DEFAULT_ENV" != "$env_name"
          conda activate $env_name
        end
      end
    end
    _ccm_conda_auto  # run once for initial directory

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
        hostname = "carbon"; # Tailscale MagicDNS
      };
      "carbon" = {
        # direct alias for carbon (used by colab tunnel)
        user = "fluoride";
        hostname = "carbon";
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
  # Secrets are decrypted at activation time using the SSH ed25519 key.
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
  };
}
