# Home-manager configuration for anthonyhan.
# Manages: fish/zsh, git, ssh, direnv, programs, Ghostty, and sops secrets.
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
  # MOONSHOT_API_KEY was intentionally excluded — secrets belong in sops, not
  # the nix store. See .sops.yaml for setup instructions.
  home.sessionPath = [
    "$HOME/.local/bin" # pipx
    "/usr/local/sbin"
  ];

  # --- Fish (primary shell) ---
  programs.fish = {
    enable = true;

    shellInit = ''
      # Suppress the default greeting
      set -g fish_greeting
    '';

    interactiveShellInit = ''
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

      # nvm — no native fish support. Consider switching to fnm.
      # For now, use bass or nvm.fish if you need nvm in fish.
      # fnm (if installed) has native fish support:
      # if type -q fnm; fnm env --shell fish | source; end

      # conda / mamba
      if test -f "$HOME/miniforge3/bin/conda"
        eval "$HOME/miniforge3/bin/conda" "shell.fish" "hook" $argv | source
      end
      if test -f "$HOME/miniforge3/bin/mamba"
        set -gx MAMBA_EXE "$HOME/miniforge3/bin/mamba"
        set -gx MAMBA_ROOT_PREFIX "$HOME/miniforge3"
        "$MAMBA_EXE" shell hook --shell fish --root-prefix "$MAMBA_ROOT_PREFIX" | source
      end

      # Antigravity
      if test -d "$HOME/.antigravity/antigravity/bin"
        fish_add_path "$HOME/.antigravity/antigravity/bin"
      end
    '';

    shellAliases = {
      rebuild = "darwin-rebuild switch --flake ~/nix-config#salvia";
      ls = "eza";
      ll = "eza -la";
      la = "eza -a";
      tree = "eza --tree";
      cat = "bat";
    };
  };

  # --- Zsh (kept for compatibility during migration) ---
  programs.zsh = {
    enable = true;

    initContent = ''
      # ghcup (Haskell)
      [ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env"

      # juliaup
      path=("$HOME/.juliaup/bin" $path)
      export PATH

      # opam (OCaml)
      [[ ! -r "$HOME/.opam/opam-init/init.zsh" ]] || source "$HOME/.opam/opam-init/init.zsh" > /dev/null 2> /dev/null

      # nvm (Node.js)
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

      # conda / mamba
      if [ -f "$HOME/miniforge3/bin/conda" ]; then
        __conda_setup="$("$HOME/miniforge3/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
        if [ $? -eq 0 ]; then
          eval "$__conda_setup"
        else
          [ -f "$HOME/miniforge3/etc/profile.d/conda.sh" ] && . "$HOME/miniforge3/etc/profile.d/conda.sh"
        fi
        unset __conda_setup
      fi
      if [ -f "$HOME/miniforge3/bin/mamba" ]; then
        export MAMBA_EXE="$HOME/miniforge3/bin/mamba"
        export MAMBA_ROOT_PREFIX="$HOME/miniforge3"
        __mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
        if [ $? -eq 0 ]; then
          eval "$__mamba_setup"
        else
          alias mamba="$MAMBA_EXE"
        fi
        unset __mamba_setup
      fi

      # Antigravity
      [ -d "$HOME/.antigravity/antigravity/bin" ] && export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
    '';
  };

  # --- Git ---
  programs.git = {
    enable = true;

    signing = {
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
      format = "ssh";
    };

    settings = {
      user = {
        name = "saliva";
        email = "sylvestria.h@gmail.com";
      };
      init.defaultBranch = "main";
      merge.conflictstyle = "zdiff3";
      diff.colorMoved = "default";
    };
  };

  # --- Delta (git pager) ---
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      dark = true;
      side-by-side = true;
    };
  };

  # --- SSH ---
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "nitrogen" = {
        user = "fluoride";
        # hostname = "nitrogen";  # TODO: set IP or hostname
      };
    };
  };

  # --- Direnv + nix-direnv ---
  programs.direnv = {
    enable = true;
    package = pkgs-stable.direnv; # unstable direnv fails CGO build on x86_64-darwin
    nix-direnv.enable = true;
    # Silence the verbose direnv output
    config.global.hide_env_diff = true;
  };

  # --- Ghostty ---
  # Installed via homebrew cask. Config managed here.
  xdg.configFile."ghostty/config".text = ''
    # Font
    font-family = JetBrainsMono Nerd Font
    font-size = 14

    # Theme
    theme = catppuccin-mocha

    # Window
    window-decoration = false
    window-padding-x = 8
    window-padding-y = 4

    # macOS
    macos-option-as-alt = true

    # Shell — fish is the default via users.users.shell
  '';

  # --- sops-nix ---
  # Secrets are decrypted at activation time using the SSH ed25519 key.
  # To set up:
  #   1. Run: ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
  #   2. Run: ssh-to-age < ~/.ssh/id_ed25519.pub   (put this in .sops.yaml)
  #   3. Create secrets: sops secrets/secrets.yaml
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    # Example secret:
    # secrets."moonshot_api_key" = {};
    # Then access via: config.sops.secrets."moonshot_api_key".path
  };

  # --- Programs managed by home-manager ---
  programs.bat.enable = true;
  programs.eza = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };
  programs.htop.enable = true;
  programs.jq.enable = true;
  programs.ripgrep.enable = true;
}
