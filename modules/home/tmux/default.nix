# Tmux — cross-platform.
# Used by: modules/home/default.nix
{ pkgs, ... }:
let
  dreamsofcode-io-catppuccin-tmux = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "catppuccin";
    version = "unstable-2023-01-06";
    src = pkgs.fetchFromGitHub {
      owner = "dreamsofcode-io";
      repo = "catppuccin-tmux";
      rev = "b4e0715356f820fc72ea8e8baf34f0f60e891718";
      sha256 = "sha256-FJHM6LJkiAwxaLd5pnAoF3a7AE1ZqHWoCpUJE0ncCA8=";
    };
  };
in
{
  home-manager.sharedModules = [
    (_: {
      programs.tmux = {
        enable = true;
        clock24 = true;
        keyMode = "vi";
        historyLimit = 100000;
        plugins = with pkgs.tmuxPlugins; [
          dreamsofcode-io-catppuccin-tmux
          sensible
          vim-tmux-navigator
        ];
        extraConfig = ''
          set -g default-shell "${pkgs.fish}/bin/fish"

          unbind C-b
          set -g prefix C-a
          bind C-a send-prefix

          set -g @catppuccin_flavour 'mocha'
          set -g repeat-time 1000
          set -g mouse on
          set -g allow-rename off
          set -g status-position top
          set -g base-index 1
          set -g pane-base-index 1
          set -g renumber-windows on
          set-window-option -g pane-base-index 1
          set -ga terminal-overrides ",*:Tc"

          bind-key -r f run-shell "tmux neww tmux-sessionizer"
          bind r command-prompt "rename-window %%"
          bind R source-file ~/.config/tmux/tmux.conf
          bind S choose-session
          bind u choose-session
          bind w list-windows
          bind * setw synchronize-panes
          bind P set pane-border-status
          bind -n C-M-c kill-pane
          bind x swap-pane -D
          bind z resize-pane -Z

          bind h select-pane -L
          bind l select-pane -R
          bind k select-pane -U
          bind j select-pane -D

          bind -r H resize-pane -L 2
          bind -r J resize-pane -D 2
          bind -r K resize-pane -U 2
          bind -r L resize-pane -R 2

          bind | split-window -h -c "#{pane_current_path}"
          bind [ split-window -h -c "#{pane_current_path}"
          bind - split-window -v -c "#{pane_current_path}"
          bind ] split-window -v -c "#{pane_current_path}"
          bind c new-window -c "#{pane_current_path}"

          bind -n S-Left  previous-window
          bind -n S-Right next-window
          bind -n C-M-h  previous-window
          bind -n C-M-l next-window

          bind-key -T copy-mode-vi v send-keys -X begin-selection
          bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
          bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
        '';
      };
    })
  ];
}
