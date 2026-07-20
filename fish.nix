# iodide's interactive fish on tin. tin has no home-manager, so the shell
# environment that modules/home/fish gives the other hosts is reconstructed here
# at the NixOS level — the cross-platform subset only.
#
# Deliberately NOT ported: the C/C++ scaffolding (cgen/crun/cbuild), conda/mamba
# auto-activation, the dev-shell template helpers (fnew/finit, which need the
# flake's ${self}/dev-shells), and the `~/NixOS#` rebuild aliases (tin is rebuilt
# remotely from the flake, not from a local checkout — see the deploy notes).
#
# mgchat is adapted: it reads the tin-specific chat-mode prompt from the vault
# replica (~/rubidium/claude/chat-mode-prompt-tin.md, kept current by the headless
# Obsidian Sync service — see modules/obsidian-vault). The prompt itself is NOT
# committed, since this repo is public and the prompt is personal.
# (Pre-replica, the prompt was scp'd out-of-band to ~/.config/claude/ — that copy
# and the tmpfiles rule below are vestigial.)
{ pkgs, username, ... }:
{
  # CLI tools the aliases/functions below assume on PATH (bat, nvim, fzf).
  environment.systemPackages = with pkgs; [
    bat
    eza
    fzf
    neovim
    trash-cli
  ];

  # ~/.config/claude holds the (out-of-band) chat-mode prompt for mgchat/mgres.
  systemd.tmpfiles.rules = [
    "d /home/${username}/.config/claude 0755 ${username} users - -"
  ];

  programs.fish = {
    shellAliases = {
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
      nv = "nvim";
      cp = "cp -iv";
      mv = "mv -iv";
      rm = "rm -vI";
      bc = "bc -ql";
      mkd = "mkdir -pv";
      tp = "${pkgs.trash-cli}/bin/trash-put";
      tpr = "${pkgs.trash-cli}/bin/trash-restore";
      grep = "grep --color=always";
    };

    shellInit = ''
      set -g fish_greeting
      set -gx FZF_DEFAULT_OPTS "--color=bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796 --color=fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6 --color=marker:#f4dbd6,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796"
    '';

    interactiveShellInit = ''
      # `… G pattern` → `… | grep pattern` — global-style abbr. The NixOS fish
      # module only accepts string shellAbbrs, so the positional form is set here.
      abbr -a G --position anywhere -- '| grep'

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

      # mgchat — Claude in chat-mode, in the shared 'mg' tmux session. Prompt is
      # the tin variant from the vault replica (synced by obsidian.service).
      # ~/.claude/CLAUDE.md imports the same prompt so remote-control sandboxes
      # (mobile app / claude.ai) get it too; interactive sessions already have it
      # as their system prompt, so it is excluded here via claudeMdExcludes to
      # avoid loading it twice. Working dir defaults to $HOME, override with
      # TIN_WORK_DIR.
      function mgchat
        set -l prompt_file "$HOME/rubidium/claude/chat-mode-prompt-tin.md"
        set -l no_dup_md '{"claudeMdExcludes":["'$HOME'/.claude/CLAUDE.md"]}'
        set -l work_dir (set -q TIN_WORK_DIR; and echo $TIN_WORK_DIR; or echo $HOME)
        if not test -f $prompt_file
          echo "mgchat: prompt not found at $prompt_file" >&2
          echo "  the vault replica should provide it — is obsidian.service running / Sync healthy?" >&2
          return 1
        end
        if test -n "$TMUX"
          cd $work_dir
          CLAUDE_CODE_NO_FLICKER=1 claude --system-prompt-file $prompt_file --settings $no_dup_md $argv
        else if tmux has-session -t mg 2>/dev/null
          tmux new-window -t mg -c $work_dir "env CLAUDE_CODE_NO_FLICKER=1 claude --system-prompt-file $prompt_file --settings '$no_dup_md' $argv; exec fish"
          tmux attach-session -t mg
        else
          tmux new-session -s mg -c $work_dir "env CLAUDE_CODE_NO_FLICKER=1 claude --system-prompt-file $prompt_file --settings '$no_dup_md' $argv; exec fish"
        end
      end
    '';
  };
}
