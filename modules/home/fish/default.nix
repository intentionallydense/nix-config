# Fish shell — cross-platform with NixOS-specific parts gated behind isLinux.
# Templates, functions, and core config work on both platforms.
# NixOS-specific aliases (rebuild, /mnt/ dirs) are linux-only.
# Used by: modules/home/default.nix
{
  self,
  pkgs,
  lib,
  terminalFileManager,
  vaultName,
  ...
}:
{
  home-manager.sharedModules = [
    (
      { config, ... }:
      {
        # Templates used by fnew/cgen functions
        xdg.configFile."fish/templates" = {
          source = ./templates;
          recursive = true;
        };

        # Fish functions (mgchat, etc.). mgkimi ships with kimi-claude-proxy module.
        xdg.configFile."fish/functions" = {
          source = ./functions;
          recursive = true;
        };

        programs.fish = {
          enable = true;

          shellInit = ''
            set -g fish_greeting
          '' + ''
            # Environment
            fish_add_path -g $HOME/.local/bin
            set -gx SOPS_AGE_KEY_FILE "$HOME/.config/sops/age/keys.txt"
            set -gx OBSIDIAN_VAULT "$HOME/Documents/Obsidian/${vaultName}"

            set -gx FZF_DEFAULT_OPTS "\
            --color=bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796 \
            --color=fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6 \
            --color=marker:#f4dbd6,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796"
          '' + lib.optionalString pkgs.stdenv.isLinux ''
            set -gx XMONAD_CONFIG_DIR (test -n "$XDG_CONFIG_HOME" && echo "$XDG_CONFIG_HOME" || echo "$HOME/.config")/xmonad
            set -gx XMONAD_DATA_DIR (test -n "$XDG_DATA_HOME" && echo "$XDG_DATA_HOME" || echo "$HOME/.local/share")/xmonad
            set -gx XMONAD_CACHE_DIR (test -n "$XDG_CACHE_HOME" && echo "$XDG_CACHE_HOME" || echo "$HOME/.cache")/xmonad
            set -gx templates "${self}/dev-shells"
          '' + lib.optionalString pkgs.stdenv.isDarwin ''
            if test -x /opt/homebrew/bin/brew
              /opt/homebrew/bin/brew shellenv | source
            else if test -x /usr/local/bin/brew
              /usr/local/bin/brew shellenv | source
            end
          '';

          interactiveShellInit = ''
            # Direnv hook
            direnv hook fish | source

            # Ctrl+L to launch file manager
            bind \cl '${terminalFileManager}; commandline -f repaint'

            # lf wrapper — cd to last dir on exit
            function lf
              set -l tmp (mktemp)
              command lf -last-dir-path="$tmp" $argv
              if test -f "$tmp"
                set -l dir (cat "$tmp")
                rm -f "$tmp"
                if test -d "$dir" -a "$dir" != (pwd)
                  cd "$dir"
                end
              end
            end

            # fnew — create new project from a dev-shell template
            function fnew
              if test -z "$argv[1]"
                echo "Usage: fnew <project-name> [template]"
                return 1
              end
              if test -d "$argv[1]"
                echo "Directory \"$argv[1]\" already exists!"
                return 1
              end
              set -l template $argv[2]
              if test -z "$template"
                set template (nix flake show ${self}/dev-shells --json 2>/dev/null \
                  | jq -r '.templates | keys[]' \
                  | fzf --prompt="Select template: ")
                test -z "$template" && echo "No template selected." && return 1
              end
              nix flake new "$argv[1]" --template ${self}/dev-shells#"$template"
              cd "$argv[1]"
              direnv allow
            end

            # finit — init current dir from a dev-shell template
            function finit
              nix flake init --template ${self}/dev-shells#$argv[1]
              direnv allow
            end

            # cgen — scaffold a C/C++ project
            function cgen
              if test -d "$argv[1]"
                echo "Directory \"$argv[1]\" already exists!"
                return 1
              end
              nix flake new $argv[1] --template ${self}/dev-shells#c-cpp
              cd $argv[1]
              cat ~/.config/fish/templates/ListTemplate.txt >> CMakeLists.txt
              mkdir src
              mkdir include
              cat ~/.config/fish/templates/HelloWorldTemplate.txt >> src/main.cpp
              direnv allow
            end

            # crun / cbuild — cmake build helpers
            function crun
              mkdir -p build
              cmake -B build
              cmake --build build
              build/main
            end

            function cbuild
              mkdir -p build
              cmake -B build
              cmake --build build
            end

            # tdev — open a tmux dev session (editor + terminal + build)
            function tdev
              set -l session_name (basename "$PWD" | tr '.:' '__')
              if tmux has-session -t "=$session_name" 2>/dev/null
                tmux attach-session -t "=$session_name"
                return
              end
              tmux new-session -d -s "$session_name" -c "$PWD"
              tmux rename-window -t "$session_name:1" "editor"
              tmux send-keys -t "$session_name:editor" "nvim" Enter
              tmux new-window -t "$session_name" -n "terminal" -c "$PWD"
              tmux new-window -t "$session_name" -n "build" -c "$PWD"
              tmux select-window -t "$session_name:editor"
              tmux attach-session -t "=$session_name"
            end

            # conda — check miniconda3 (carbon) then miniforge3 (macOS)
            for conda_root in "$HOME/miniconda3" "$HOME/miniforge3"
              if test -f "$conda_root/bin/conda"
                eval "$conda_root/bin/conda" "shell.fish" "hook" $argv | source
                break
              end
            end

            # mamba — miniforge3 ships it; miniconda3 doesn't
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
          '';

          shellAbbrs = {
            # Global-style abbreviations (fish equivalent of zsh global aliases)
            G = {
              position = "anywhere";
              expansion = "| grep";
            };
          };

          shellAliases = {
            # Universal aliases
            cls = "clear";
            tml = "tmux list-sessions";
            tma = "tmux attach";
            tms = "tmux attach -t (tmux ls -F '#{session_name}: #{session_path} (#{session_windows} windows)' | fzf | cut -d: -f1)";
            l = "${pkgs.eza}/bin/eza -lh --icons=auto";
            ls = "${pkgs.eza}/bin/eza -1 --icons=auto";
            ll = "${pkgs.eza}/bin/eza -lha --icons=auto --sort=name --group-directories-first";
            la = "${pkgs.eza}/bin/eza -a --icons=auto";
            ld = "${pkgs.eza}/bin/eza -lhD --icons=auto";
            tree = "${pkgs.eza}/bin/eza --icons=auto --tree";
            cat = "bat";
            vc = "code --disable-gpu";
            nv = "nvim";
            cp = "cp -iv";
            mv = "mv -iv";
            rm = "rm -vI";
            bc = "bc -ql";
            mkd = "mkdir -pv";
            tp = "${pkgs.trash-cli}/bin/trash-put";
            tpr = "${pkgs.trash-cli}/bin/trash-restore";
            grep = "grep --color=always";
            claudee = "CLAUDE_CODE_NO_FLICKER=1 claude --dangerously-skip-permissions";
            claudey = "CLAUDE_CODE_NO_FLICKER=1 claude --dangerously-skip-permissions --resume";
          } // lib.optionalAttrs pkgs.stdenv.isLinux {
            # NixOS-specific aliases
            nf = "${pkgs.microfetch}/bin/microfetch";
            list-gens = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system/";
            update-input = "nix flake update $argv";
            sysup = "sudo nixos-rebuild switch --flake ~/NixOS# --upgrade-all --show-trace";
            rebuild = "sudo nixos-rebuild switch --flake ~/NixOS# --show-trace";
            nrs = "git -C ~/NixOS pull origin main && sudo nixos-rebuild switch --flake ~/NixOS# --show-trace";
            dots = "cd ~/NixOS/";
            games = "cd /mnt/games/";
            work = "cd /mnt/work/";
            media = "cd /mnt/work/media/";
            projects = "cd /mnt/work/Projects/";
            proj = "cd /mnt/work/Projects/";
            dev = "cd /mnt/work/Projects/";
          } // lib.optionalAttrs pkgs.stdenv.isDarwin {
            # macOS-specific aliases
            rebuild = "sudo darwin-rebuild switch --flake ~/nix-config";
            nrs = "git -C ~/nix-config pull origin main && sudo darwin-rebuild switch --flake ~/nix-config";
          };
        };
      }
    )
  ];
}
