# Zsh — cross-platform with NixOS-specific parts gated behind isLinux.
# The p10k theme, templates, and core config work on both platforms.
# NixOS-specific aliases (rebuild, /mnt/ dirs) are linux-only.
# Used by: modules/home/default.nix
{
  self,
  pkgs,
  lib,
  terminalFileManager,
  ...
}:
{
  home-manager.sharedModules = [
    (
      { config, ... }:
      {
        xdg.configFile."zsh/.p10k.zsh".source = ./.p10k.zsh;
        xdg.configFile."zsh/templates" = {
          source = ./templates;
          recursive = true;
        };
        programs.zsh = {
          enable = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          enableCompletion = true;
          history.size = 100000;
          history.path = "${config.xdg.dataHome}/zsh/history";
          dotDir = "${config.xdg.configHome}/zsh";
          oh-my-zsh = {
            enable = true;
            plugins = [
              "git"
              "gitignore"
              "z"
            ];
          };
          initContent = ''
            # Powerlevel10k Zsh theme
            source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
            test -f ~/.config/zsh/.p10k.zsh && source ~/.config/zsh/.p10k.zsh

            # Direnv hook
            eval "$(direnv hook zsh)"

            # Key Bindings
            bindkey '^l' "${terminalFileManager}\r"
            bindkey '^a' beginning-of-line
            bindkey '^e' end-of-line

            # Options
            unsetopt menu_complete
            unsetopt flowcontrol
            setopt prompt_subst
            setopt always_to_end
            setopt append_history
            setopt auto_menu
            setopt complete_in_word
            setopt extended_history
            setopt hist_expire_dups_first
            setopt hist_ignore_dups
            setopt hist_ignore_space
            setopt hist_verify
            setopt inc_append_history
            setopt share_history

            function lf {
                tmp="$(mktemp)"
                command lf -last-dir-path="$tmp" "$@"
                if [ -f "$tmp" ]; then
                    dir="$(cat "$tmp")"
                    rm -f "$tmp"
                    if [ -d "$dir" ]; then
                        if [ "$dir" != "$(pwd)" ]; then
                            cd "$dir"
                        fi
                    fi
                fi
            }

            function fnew {
              if [ -z "$1" ]; then
                echo "Usage: fnew <project-name> [template]"
                return 1
              fi
              if [ -d "$1" ]; then
                echo "Directory \"$1\" already exists!"
                return 1
              fi
              local template="$2"
              if [ -z "$template" ]; then
                template=$(nix flake show ${self}/dev-shells --json 2>/dev/null \
                  | jq -r '.templates | keys[]' \
                  | fzf --prompt="Select template: ")
                [ -z "$template" ] && echo "No template selected." && return 1
              fi
              nix flake new "$1" --template ${self}/dev-shells#"$template"
              cd "$1"
              direnv allow
            }

            function finit {
              nix flake init --template ${self}/dev-shells#$1
              direnv allow
            }

            function cgen {
              if [ -d "$1" ]; then
                echo "Directory \"$1\" already exists!"
                return 1
              fi
              nix flake new $1 --template ${self}/dev-shells#c-cpp
              cd $1
              cat ~/.config/zsh/templates/ListTemplate.txt >> CMakeLists.txt
              mkdir src
              mkdir include
              cat ~/.config/zsh/templates/HelloWorldTemplate.txt >> src/main.cpp
              direnv allow
            }

            function crun {
              mkdir build 2> /dev/null
              cmake -B build
              cmake --build build
              build/main
            }

            function cbuild {
              mkdir build 2> /dev/null
              cmake -B build
              cmake --build build
            }

            function tdev {
              local session_name=$(basename "$PWD" | tr '.:' '__')
              if tmux has-session -t "=$session_name" 2>/dev/null; then
                tmux attach-session -t "=$session_name"
                return
              fi
              tmux new-session -d -s "$session_name" -c "$PWD"
              tmux rename-window -t "$session_name:1" "editor"
              tmux send-keys -t "$session_name:editor" "nvim" Enter
              tmux new-window -t "$session_name" -n "terminal" -c "$PWD"
              tmux new-window -t "$session_name" -n "build" -c "$PWD"
              tmux select-window -t "$session_name:editor"
              tmux attach-session -t "=$session_name"
            }
          '';
          envExtra = ''
            export PATH="$HOME/.local/bin:$PATH"

            export FZF_DEFAULT_OPTS=" \
            --color=bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796 \
            --color=fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6 \
            --color=marker:#f4dbd6,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796"
          '' + lib.optionalString pkgs.stdenv.isLinux ''
            export XMONAD_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/xmonad"
            export XMONAD_DATA_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/xmonad"
            export XMONAD_CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/xmonad"

            export templates="${self}/dev-shells"
          '';
          shellGlobalAliases = {
            UUID = "$(uuidgen | tr -d \\n)";
            G = "| grep";
          };
          shellAliases = {
            # Universal aliases
            cls = "clear";
            tml = "tmux list-sessions";
            tma = "tmux attach";
            tms = "tmux attach -t $(tmux ls -F '#{session_name}: #{session_path} (#{session_windows} windows)' | fzf | cut -d: -f1)";
            l = "${pkgs.eza}/bin/eza -lh  --icons=auto";
            ls = "${pkgs.eza}/bin/eza -1   --icons=auto";
            ll = "${pkgs.eza}/bin/eza -lha --icons=auto --sort=name --group-directories-first";
            ld = "${pkgs.eza}/bin/eza -lhD --icons=auto";
            tree = "${pkgs.eza}/bin/eza --icons=auto --tree";
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
          } // lib.optionalAttrs pkgs.stdenv.isLinux {
            # NixOS-specific aliases
            nf = "${pkgs.microfetch}/bin/microfetch";
            list-gens = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system/";
            find-store-path = ''function { nix-shell -p $1 --command "nix eval -f \"<nixpkgs>\" --raw $1" }'';
            update-input = "nix flake update $@";
            sysup = "sudo nixos-rebuild switch --flake ~/NixOS# --upgrade-all --show-trace";
            dots = "cd ~/NixOS/";
            games = "cd /mnt/games/";
            work = "cd /mnt/work/";
            media = "cd /mnt/work/media/";
            projects = "cd /mnt/work/Projects/";
            proj = "cd /mnt/work/Projects/";
            dev = "cd /mnt/work/Projects/";
          } // lib.optionalAttrs pkgs.stdenv.isDarwin {
            # macOS-specific aliases
            rebuild = "sudo darwin-rebuild switch --flake ~/projects/active/nix-config";
            publish = "python3 ~/projects/active/intentionallydense/publish.py --go --push";
            publish-dry = "python3 ~/projects/active/intentionallydense/publish.py";
          };
        };
      }
    )
  ];
}
